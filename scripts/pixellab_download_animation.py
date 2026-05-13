from __future__ import annotations

import argparse
import json
import math
import os
import re
import shutil
import urllib.request
import zipfile
from pathlib import Path
from typing import Any


API_BASE_URL = "https://api.pixellab.ai/characters"
RAW_ROOT = Path("assets/pixellab_characters")
ACTION_ORDER = ("Idle", "Walk", "Fight")
DIRECTION_ORDER = ("east", "south-east", "south")
PATTERNS = {
    "Idle": ("idle", "breath", "stance", "animating"),
    "Walk": ("walk", "run", "dash", "animation"),
    "Fight": (
        "fight",
        "attack",
        "punch",
        "kick",
        "uppercut",
        "roundhouse",
        "cross",
        "hurricane",
        "high",
        "slash",
        "strike",
    ),
}


def parse_args(target_root: Path) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=f"Download a PixelLab character into {target_root}."
    )
    parser.add_argument("character_id", nargs="?", help="PixelLab character id.")
    parser.add_argument("--character-id", dest="character_id_option")
    parser.add_argument("--character-name", default="")
    parser.add_argument(
        "--no-ui",
        action="store_true",
        help="Skip the picker UI and infer Idle, Walk, and Fight automatically.",
    )
    args = parser.parse_args()
    args.character_id = args.character_id_option or args.character_id
    if not args.character_id:
        parser.error("character_id is required.")
    return args


def repo_root() -> Path:
    return Path(__file__).resolve().parent.parent


def safe_folder_name(name: str) -> str:
    clean_name = name.strip()
    if len(clean_name) > 80:
        match = re.search(r"known as the ([^.]+)", clean_name, flags=re.IGNORECASE)
        if match:
            clean_name = match.group(1).strip()
    if len(clean_name) > 80:
        clean_name = clean_name[:80].strip()

    invalid_chars = '<>:"/\\|?*'
    return "".join("_" if char in invalid_chars or ord(char) < 32 else char for char in clean_name)


def download_zip(character_id: str, zip_path: Path) -> None:
    api_key = os.environ.get("PIXELLAB_API_KEY", "").strip()
    if not api_key:
        raise RuntimeError("PIXELLAB_API_KEY is not set.")

    request = urllib.request.Request(
        f"{API_BASE_URL}/{character_id}/zip",
        headers={"Authorization": f"Bearer {api_key}"},
    )
    with urllib.request.urlopen(request) as response:
        zip_path.write_bytes(response.read())


def read_export(metadata_path: Path) -> dict[str, Any]:
    metadata = json.loads(metadata_path.read_text(encoding="utf-8"))
    states = metadata.get("states")
    if isinstance(states, list) and states:
        return states[0]
    return metadata


def sync_state_export_folders(raw_character_folder: Path, export: dict[str, Any]) -> None:
    state_folder = str(export.get("folder", "")).strip()
    if not state_folder:
        return

    state_root = raw_character_folder / Path(state_folder)
    for folder_name in ("animations", "rotations"):
        source = state_root / folder_name
        if not source.exists():
            continue
        destination = raw_character_folder / folder_name
        if destination.exists():
            shutil.rmtree(destination)
        shutil.copytree(source, destination)


def get_animations(export: dict[str, Any]) -> dict[str, dict[str, list[str]]]:
    frames = export.get("frames", {})
    animations = frames.get("animations", {})
    if not isinstance(animations, dict) or not animations:
        raise RuntimeError("metadata.json does not contain animations.")
    return animations


def select_animation_name(
    animations: dict[str, dict[str, list[str]]],
    kind: str,
    used: set[str],
) -> str:
    for pattern in PATTERNS[kind]:
        for name, directions in animations.items():
            if name in used:
                continue
            if re.search(pattern, name, flags=re.IGNORECASE) and "east" in directions:
                used.add(name)
                return name

    for pattern in PATTERNS[kind]:
        for name in animations:
            if name in used:
                continue
            if re.search(pattern, name, flags=re.IGNORECASE):
                used.add(name)
                return name

    for name in animations:
        if name not in used:
            used.add(name)
            return name

    raise RuntimeError(f"Could not find an animation for {kind}.")


def select_direction(animation: dict[str, list[str]]) -> str:
    for direction in DIRECTION_ORDER:
        if direction in animation:
            return direction
    for direction in animation:
        return direction
    raise RuntimeError("Animation does not contain any direction folders.")


def copy_animation_frames(
    raw_character_folder: Path,
    target_character_folder: Path,
    target_action: str,
    relative_frames: list[str],
) -> None:
    if not relative_frames:
        raise RuntimeError(f"{target_action} does not contain any frames.")

    destination = target_character_folder / target_action
    if destination.exists():
        shutil.rmtree(destination)
    destination.mkdir(parents=True, exist_ok=True)

    for relative_frame in relative_frames:
        source = raw_character_folder / Path(relative_frame)
        if not source.exists():
            raise RuntimeError(f"Missing source animation frame: {source}")
        shutil.copy2(source, destination / source.name)


def get_east_animations(
    animations: dict[str, dict[str, list[str]]],
) -> dict[str, list[str]]:
    return {
        name: directions["east"]
        for name, directions in animations.items()
        if "east" in directions and directions["east"]
    }


def automatic_frame_mapping(
    animations: dict[str, dict[str, list[str]]],
) -> dict[str, list[str]]:
    used: set[str] = set()
    mapping: dict[str, list[str]] = {}
    for action in ACTION_ORDER:
        animation_name = select_animation_name(animations, action, used)
        animation = animations[animation_name]
        direction = select_direction(animation)
        mapping[action] = animation[direction]
    return mapping


def select_east_animation_name(
    east_animations: dict[str, list[str]],
    kind: str,
    used: set[str],
) -> str:
    for pattern in PATTERNS[kind]:
        for name in east_animations:
            if name in used:
                continue
            if re.search(pattern, name, flags=re.IGNORECASE):
                used.add(name)
                return name

    for name in east_animations:
        if name not in used:
            used.add(name)
            return name

    raise RuntimeError(f"Could not find an east-facing animation for {kind}.")


def automatic_east_frame_mapping(
    east_animations: dict[str, list[str]],
) -> dict[str, list[str]]:
    used: set[str] = set()
    mapping: dict[str, list[str]] = {}
    for action in ACTION_ORDER:
        animation_name = select_east_animation_name(east_animations, action, used)
        mapping[action] = east_animations[animation_name]
    return mapping


def open_animation_picker(
    raw_character_folder: Path,
    east_animations: dict[str, list[str]],
    defaults: dict[str, list[str]],
) -> dict[str, list[str]]:
    import tkinter as tk
    from tkinter import messagebox, ttk

    if not east_animations:
        raise RuntimeError("No east-facing animations were found.")

    root = tk.Tk()
    root.title("Select PixelLab animations")
    root.geometry("1180x760")

    selected_animation: dict[str, tk.StringVar] = {}
    frame_vars: dict[tuple[str, str, int], tk.BooleanVar] = {}
    images: list[tk.PhotoImage] = []
    result: dict[str, list[str]] = {}

    title = ttk.Label(
        root,
        text="Choose an animation and frames for each action",
        font=("Segoe UI", 14, "bold"),
    )
    title.pack(anchor="w", padx=12, pady=(12, 4))

    hint = ttk.Label(
        root,
        text="Only animations with an east direction are shown. Checked frames are copied in order.",
    )
    hint.pack(anchor="w", padx=12, pady=(0, 10))

    canvas = tk.Canvas(root, highlightthickness=0)
    y_scroll = ttk.Scrollbar(root, orient="vertical", command=canvas.yview)
    x_scroll = ttk.Scrollbar(root, orient="horizontal", command=canvas.xview)
    body = ttk.Frame(canvas)
    body.bind(
        "<Configure>",
        lambda _event: canvas.configure(scrollregion=canvas.bbox("all")),
    )
    canvas.create_window((0, 0), window=body, anchor="nw")
    canvas.configure(yscrollcommand=y_scroll.set, xscrollcommand=x_scroll.set)
    canvas.pack(side="left", fill="both", expand=True, padx=(12, 0), pady=(0, 12))
    y_scroll.pack(side="right", fill="y", pady=(0, 12))
    x_scroll.pack(side="bottom", fill="x", padx=12)

    def default_name_for(action: str) -> str:
        default_frames = defaults.get(action, [])
        for animation_name, frames in east_animations.items():
            if frames == default_frames:
                return animation_name
        return next(iter(east_animations))

    def make_thumbnail(relative_frame: str) -> tk.PhotoImage:
        image = tk.PhotoImage(file=str(raw_character_folder / Path(relative_frame)))
        largest_side = max(image.width(), image.height())
        subsample = max(1, math.ceil(largest_side / 72))
        if subsample > 1:
            image = image.subsample(subsample, subsample)
        images.append(image)
        return image

    for action in ACTION_ORDER:
        section = ttk.LabelFrame(body, text=f"{action} action")
        section.pack(fill="x", expand=True, padx=4, pady=8)

        selected_animation[action] = tk.StringVar(value=default_name_for(action))
        for animation_name, frames in east_animations.items():
            row = ttk.Frame(section)
            row.pack(fill="x", anchor="w", padx=8, pady=6)

            radio = ttk.Radiobutton(
                row,
                text=f"{animation_name} ({len(frames)} frames)",
                variable=selected_animation[action],
                value=animation_name,
            )
            radio.pack(side="left", anchor="n", padx=(0, 10))

            frame_strip = ttk.Frame(row)
            frame_strip.pack(side="left", anchor="w")
            for index, relative_frame in enumerate(frames):
                frame_cell = ttk.Frame(frame_strip)
                frame_cell.pack(side="left", padx=4)

                thumbnail = make_thumbnail(relative_frame)
                image_label = ttk.Label(frame_cell, image=thumbnail)
                image_label.pack()

                checked = tk.BooleanVar(value=True)
                frame_vars[(action, animation_name, index)] = checked
                checkbox = ttk.Checkbutton(
                    frame_cell,
                    text=f"{index:03d}",
                    variable=checked,
                )
                checkbox.pack()

    button_bar = ttk.Frame(root)
    button_bar.pack(fill="x", padx=12, pady=(0, 12))

    def confirm() -> None:
        result.clear()
        for action in ACTION_ORDER:
            animation_name = selected_animation[action].get()
            selected_frames = [
                frame
                for index, frame in enumerate(east_animations[animation_name])
                if frame_vars[(action, animation_name, index)].get()
            ]
            if not selected_frames:
                messagebox.showerror(
                    "Missing frames",
                    f"Select at least one frame for {action}.",
                )
                return
            result[action] = selected_frames
        root.destroy()

    def cancel() -> None:
        result.clear()
        root.destroy()

    ttk.Button(button_bar, text="Copy selected frames", command=confirm).pack(
        side="right", padx=(8, 0)
    )
    ttk.Button(button_bar, text="Cancel", command=cancel).pack(side="right")

    root.mainloop()
    if not result:
        raise RuntimeError("Animation selection was cancelled.")
    return result


def download_animation(
    character_id: str,
    target_root: Path,
    character_name: str = "",
    interactive: bool = True,
) -> None:
    root = repo_root()
    zip_path = root / f"pixellab_{character_id}.zip"
    raw_character_folder = root / RAW_ROOT / character_id

    if raw_character_folder.exists():
        shutil.rmtree(raw_character_folder)
    raw_character_folder.mkdir(parents=True, exist_ok=True)

    try:
        download_zip(character_id, zip_path)
        with zipfile.ZipFile(zip_path) as archive:
            archive.extractall(raw_character_folder)
    finally:
        if zip_path.exists():
            zip_path.unlink()

    export = read_export(raw_character_folder / "metadata.json")
    sync_state_export_folders(raw_character_folder, export)

    folder_name = safe_folder_name(
        character_name or str(export.get("character", {}).get("name", character_id))
    )
    target_character_folder = root / target_root / folder_name
    target_character_folder.mkdir(parents=True, exist_ok=True)

    animations = get_animations(export)
    if interactive:
        east_animations = get_east_animations(animations)
        defaults = automatic_east_frame_mapping(east_animations)
        frame_mapping = open_animation_picker(
            raw_character_folder,
            east_animations,
            defaults,
        )
    else:
        frame_mapping = automatic_frame_mapping(animations)

    for action, frames in frame_mapping.items():
        copy_animation_frames(
            raw_character_folder,
            target_character_folder,
            action,
            frames,
        )

    print(f"Downloaded {character_id} as {folder_name}")
    for action in ACTION_ORDER:
        frame_count = len(list((target_character_folder / action).glob("*.png")))
        print(f"{action}: {frame_count} frames")


def main(target_root: Path) -> None:
    args = parse_args(target_root)
    download_animation(
        args.character_id,
        target_root,
        args.character_name,
        interactive=not args.no_ui,
    )
