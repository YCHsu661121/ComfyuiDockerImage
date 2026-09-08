#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
novel-to-h3-plan.py — 讀小說 txt，依段落(空行)切成分鏡，用 llama-cpp-python 把每段
原文轉成 MiniMax H3 需要的視覺化 prompt，寫回 ComfyUI-MiniMaxH3-Context-Loop 的
「Production Plan」節點，產生一份可直接拖進 ComfyUI 執行、逐段接續生成的超長影片工作流程 JSON。

前置需求：
  - image 內已隨 Dockerfile 建好 CUDA 版 llama-cpp-python，容器內可直接 import，不需另外安裝
  - easy-install-nodes.sh 已安裝 custom_nodes/ComfyUI-MiniMaxH3-Context-Loop
    （提供 Production Plan / Loop / Assemble 節點鏈）與其依賴的
    custom_nodes/ComfyUI-H3-Motion-Context-MultiRef
  - 範本工作流程檔案，預設路徑（掛在 /mnt/comfyui/custom_nodes 底下）：
      /app/custom_nodes/ComfyUI-MiniMaxH3-Context-Loop/example_workflows/T2V Normal - MiniMax H3 0.6.json
  - entrypoint.sh 已自動下載 GGUF 模型到 /app/models/LLM/gemma-4-12b/*.gguf

容器內執行範例（novel.txt 先放進 /mnt/comfyui/input/，本腳本先 docker cp 進容器）：
  docker cp novel-to-h3-plan.py comfyui:/app/novel-to-h3-plan.py
  docker exec -it comfyui python /app/novel-to-h3-plan.py \\
      --novel /app/input/novel.txt \\
      --run-name my_story \\
      --output /app/input/my_story_workflow.json \\
      --llm-model /app/models/LLM/gemma-4-12b/gemma-4-12b-it-UD-Q4_K_XL.gguf \\
      --seconds-per-scene 8

產生的 /mnt/comfyui/input/my_story_workflow.json（對應容器內 /app/input/）從瀏覽器下載後
直接拖進 ComfyUI 網頁即可；之後照 Context-Loop 的 Getting Started 流程操作：設定四個模型
loader → Queue → Loop 逐段生成 → Review Gate 逐段核可 → 全部核可後 Assemble 自動輸出最終長片 MP4。
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

DEFAULT_STEPS = 20
DEFAULT_FPS = 24

SYSTEM_PROMPT_ZH = """你是 MiniMax H3 影片模型的分鏡提示詞撰寫者。
輸入是一段小說原文，請把它改寫成一個「畫面轉場」的分鏡指令，並嚴格輸出以下三段格式，
不要輸出任何其他文字或標題：

integrated_multimodal_description:
[Shot 1] 用具體、可拍攝的鏡頭語言描述這段文字對應的畫面：場景、人物外觀與動作、鏡頭運動、
光線與氛圍。保持與原文一致的角色與事件，避免加入原文沒有的新角色。

overall_soundscape:
描述這段畫面應有的環境音、動作音效。

non_diegetic_music:
簡短描述配樂風格，若不需要配樂請寫「No non-diegetic music.」
"""


def split_paragraphs(text: str, min_chars: int = 2) -> list[str]:
    """依空行切段，過濾掉過短的雜訊段落。"""
    raw_parts = re.split(r"\n\s*\n+", text.strip())
    paragraphs = [p.strip() for p in raw_parts]
    return [p for p in paragraphs if len(p) >= min_chars]


def h3_length_frames(seconds: float, fps: int = DEFAULT_FPS) -> int:
    """對齊 MiniMax H3 的 17k+5 合法幀數格線（與附件工作流程的 ComfyMathExpression 相同公式）。"""
    n = max(5, round(seconds * fps))
    return n + (5 - (n % 17)) % 17


def slugify(index: int, text: str) -> str:
    ascii_only = re.sub(r"[^0-9A-Za-z]+", "_", text)[:24].strip("_").lower()
    return f"scene_{index:03d}" + (f"_{ascii_only}" if ascii_only else "")


def sanitize_run_name(name: str) -> str:
    return re.sub(r"[^0-9A-Za-z_\-]+", "_", name.strip()) or "novel_run"


class PromptWriter:
    """用 llama-cpp-python 把小說段落改寫成 H3 分鏡 prompt；沒裝套件或沒給模型路徑就直接包裝原文。"""

    def __init__(self, model_path: str | None, language: str = "zh"):
        self.llm = None
        self.language = language
        if model_path:
            try:
                from llama_cpp import Llama  # type: ignore
            except ImportError:
                print(
                    "[WARN] 找不到 llama-cpp-python（正常情況下 image 已內建），退回「原文直接包裝」模式。",
                    file=sys.stderr,
                )
                return
            print(f"[novel-to-h3-plan] 載入 GGUF 模型: {model_path}")
            self.llm = Llama(
                model_path=model_path,
                n_ctx=4096,
                n_gpu_layers=-1,
                verbose=False,
            )

    def write(self, paragraph: str) -> str:
        if self.llm is None:
            return self._fallback(paragraph)
        try:
            resp = self.llm.create_chat_completion(
                messages=[
                    {"role": "system", "content": SYSTEM_PROMPT_ZH},
                    {"role": "user", "content": paragraph},
                ],
                max_tokens=500,
                temperature=0.7,
            )
            content = resp["choices"][0]["message"]["content"].strip()
            return content or self._fallback(paragraph)
        except Exception as exc:  # noqa: BLE001 - 生成失敗時不中斷整批
            print(f"[WARN] LLM 生成失敗，改用原文包裝: {exc}", file=sys.stderr)
            return self._fallback(paragraph)

    @staticmethod
    def _fallback(paragraph: str) -> str:
        return (
            "integrated_multimodal_description:\n"
            f"[Shot 1] {paragraph}\n\n"
            "overall_soundscape:\n"
            "Ambient sound matching the scene.\n\n"
            "non_diegetic_music:\n"
            "No non-diegetic music."
        )


def build_plan(paragraphs: list[str], writer: PromptWriter, seconds_per_scene: float,
               fps: int, seed_base: int) -> dict:
    length = h3_length_frames(seconds_per_scene, fps)
    shots = []
    for i, para in enumerate(paragraphs):
        prompt = writer.write(para)
        shots.append(
            {
                "id": slugify(i, para),
                "prompt": prompt,
                "length": length,
                "seed": str(seed_base + i),
            }
        )
        print(f"[novel-to-h3-plan] 完成第 {i + 1}/{len(paragraphs)} 段分鏡")
    return {"defaults": {"steps": DEFAULT_STEPS}, "shots": shots}


def inject_plan_into_template(template_path: Path, plan: dict, run_name: str) -> dict:
    workflow = json.loads(template_path.read_text(encoding="utf-8"))
    target = None
    for node in workflow.get("nodes", []):
        if node.get("type") == "MiniMaxH3ChainPlanModern":
            target = node
            break
    if target is None:
        raise SystemExit(
            "在範本工作流程裡找不到 MiniMaxH3ChainPlanModern（Production Plan）節點，"
            "請確認 --template 指向的是 ComfyUI-MiniMaxH3-Context-Loop 的範例工作流程。"
        )
    widgets = target.get("widgets_values")
    if not widgets:
        raise SystemExit("Production Plan 節點沒有 widgets_values，範本檔案可能不相容。")
    widgets[0] = json.dumps(plan, ensure_ascii=False)
    if len(widgets) > 1:
        widgets[1] = run_name
    return workflow


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--novel", required=True, type=Path, help="小說 txt 檔案路徑")
    parser.add_argument("--run-name", required=True, help="這次長片產出的專案名稱（英數/底線）")
    parser.add_argument(
        "--template",
        default="/app/custom_nodes/ComfyUI-MiniMaxH3-Context-Loop/example_workflows/T2V Normal - MiniMax H3 0.6.json",
        type=Path,
        help="Context-Loop 範例工作流程 JSON 路徑",
    )
    parser.add_argument("--output", required=True, type=Path, help="輸出的 ComfyUI 工作流程 JSON 路徑")
    parser.add_argument("--llm-model", default=None, help="llama-cpp-python 用的 GGUF 模型路徑（不給就直接包裝原文）")
    parser.add_argument("--seconds-per-scene", type=float, default=8.0, help="每段小說對應的影片秒數（預設 8 秒）")
    parser.add_argument("--fps", type=int, default=DEFAULT_FPS)
    parser.add_argument("--seed-base", type=int, default=1000)
    parser.add_argument("--min-chars", type=int, default=2, help="段落最少字數，過短的段落會被忽略")
    parser.add_argument("--max-scenes", type=int, default=None, help="只處理前 N 段，方便先小量測試")
    args = parser.parse_args()

    text = args.novel.read_text(encoding="utf-8")
    paragraphs = split_paragraphs(text, args.min_chars)
    if args.max_scenes:
        paragraphs = paragraphs[: args.max_scenes]
    if not paragraphs:
        raise SystemExit("小說切段後沒有任何內容，請確認檔案編碼與段落是否以空行分隔。")
    print(f"[novel-to-h3-plan] 共切出 {len(paragraphs)} 段分鏡")

    writer = PromptWriter(args.llm_model)
    plan = build_plan(paragraphs, writer, args.seconds_per_scene, args.fps, args.seed_base)

    run_name = sanitize_run_name(args.run_name)
    workflow = inject_plan_into_template(args.template, plan, run_name)

    args.output.write_text(json.dumps(workflow, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"[novel-to-h3-plan] 已寫出工作流程: {args.output}")
    print("接下來：把這個 json 拖進 ComfyUI，設定四個模型 loader 後 Queue 即可逐段生成。")


if __name__ == "__main__":
    main()
