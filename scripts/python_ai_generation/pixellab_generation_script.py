from typing import Optional
from open_ai_pixel_art import OpenAIPixelArtGenerator, PixelArtResult
from pixellab_animator import PixellabAnimator, PixellabAnimationResult
from sys import argv
from data_format import (
    AnimationRequest,
    AnimationResult,
    RequestLoadResult,
    load_request_from_file,
)
from pathlib import Path
from utils import new_folder
from copy import copy

DEFAULT_ANIMATION_FOLDER_NAME: str = "ai_animations"


def generate_animations() -> AnimationResult:
    result: AnimationResult = AnimationResult()
    try:
        if len(argv) < 2:
            result.add_err("Request file path not provided")
            return result

        request_file_path: str = argv[1]
        if not Path(request_file_path).is_file():
            result.add_err(f"Invalid file path provided: {request_file_path}")
            return result

        request_load_res: RequestLoadResult = load_request_from_file(request_file_path)
        animation_req: Optional[AnimationRequest] = request_load_res.request
        if animation_req is None:
            result.errors.extend(request_load_res.errors)
            result.add_err(
                f"Failed to load animation request from file: {request_load_res.errors}"
            )
            return result

        result.char_data = animation_req.char_data

        animation_folder_name: str = animation_req.char_data.title
        if len(animation_folder_name) == 0:
            animation_folder_name = DEFAULT_ANIMATION_FOLDER_NAME
        animation_folder_path_str: str = f"{animation_folder_name}"
        if len(animation_req.base_folder) > 0:
            animation_folder_path_str = (
                f"{animation_req.base_folder}/{animation_folder_path_str}"
            )
        animation_folder_path: str = new_folder(animation_folder_path_str)
        if (
            animation_req.char_data.ref_image_path is None
            or len(animation_req.char_data.ref_image_path) == 0
        ):
            pixel_art_generator: OpenAIPixelArtGenerator = OpenAIPixelArtGenerator()
            image_save_path: str = (
                f"{animation_folder_path}/{animation_folder_name}_ref_image"
            )
            pixel_art_result: PixelArtResult = (
                pixel_art_generator.generate_pixel_art_character(
                    animation_req.char_data.description,
                    image_save_path,
                )
            )
            result.errors.extend(pixel_art_result.errors)
            if pixel_art_result.gen_image_path is not None:
                animation_req.char_data.ref_image_path = pixel_art_result.gen_image_path
            else:
                result.add_err("Failed to generate pixel art with open ai")
                return result
        animator: PixellabAnimator = PixellabAnimator()
        pixellab_result: PixellabAnimationResult = animator.generate_animations(
            animation_req, animation_folder_path
        )
        result.action_folders = copy(pixellab_result.action_folders)
        result.errors.extend(pixellab_result.errors)
        return result
    except Exception as e:
        result.add_err(f"Error when generating animations: {e}")
        return result


if __name__ == "__main__":
    animation_result: AnimationResult = generate_animations()
    maybe_save_path: Optional[str] = animation_result.save_to_file()
    if maybe_save_path is not None:
        print(maybe_save_path)
    else:
        print("")
