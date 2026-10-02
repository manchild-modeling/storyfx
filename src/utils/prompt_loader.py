from pathlib import Path

PROJECT_ROOT = Path.cwd().parents[1]

PROMPT_DIR = PROJECT_ROOT / "configs" / "prompts" / "storyfx"
DATA_DIR = PROJECT_ROOT / "data"


def load_prompt(prompt_name: str, excerpt_name: str) -> str:
    prompt_path = PROMPT_DIR / F"{prompt_name}.txt"
    excerpt_path = DATA_DIR / excerpt_name /"raw" / f"{excerpt_name}.txt"

    prompt_template = prompt_path.read_text(encoding="utf-8").strip()
    excerpt_text = excerpt_path.read_text(encoding="utf-8").strip()

    full_prompt = (
        f"{prompt_template}\n\n"
        f"### INPUT NARRATIVE \n\n"
        f"{excerpt_text}"
    )

    return full_prompt


if __name__ == "__main__":
    prompt = load_prompt(
        "segment_specification",
        "excerpt_000"
    )

    print(prompt)