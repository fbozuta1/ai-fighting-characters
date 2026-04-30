from pixellab import Client as PLClient
from pixellab.animate_with_text import (
    AnimateWithTextResponse,
    ImageSize,
    animate_with_text,
)
from PIL.Image import Image as PILImage
from PIL.Image import open as pil_image_open
from typing import Optional, List, Dict
from cv2 import imread, resize, imwrite, IMREAD_UNCHANGED, INTER_NEAREST
from utils import (
    new_folder,
    new_image_file_path,
    image_path_with_extension,
    find_first_image_in_folder,
)
from os import environ
from data_format import AnimationRequest
from dataclasses import dataclass, field
from time import sleep


@dataclass
class PixellabAnimationResult:
    action_folders: Dict[str, str] = field(default_factory=dict)
    errors: List[str] = field(default_factory=list)

    def add_err(self, err: str):
        self.errors.append(err)

    def combine_with(self, result: "PixellabAnimationResult"):
        self.action_folders.update(result.action_folders)
        self.errors.extend(result.errors)


class PixellabAnimator:
    __client: PLClient

    __BASE_PROMPT: str = (
        "Generate animation frames for the character provided in the image attachment. The character graphics and coloring remain the same in the attched reference image. Character description:"
    )
    __PIXELLAB_API_KEY: str = "PIXELLAB_API_KEY"
    __DEFAULT_FOLDER_BASE_PATH: str = "animation_frames"
    __DEFAULT_FOLDER_NAME: str = "ai_character"

    __BASE_URL: str = "https://api.pixellab.ai/v2"

    def __init__(
        self,
    ):
        api_key: Optional[str] = environ.get(self.__PIXELLAB_API_KEY)
        if api_key is None:
            raise Exception(
                f"Api key not defined, please get an api key and set the {self.__PIXELLAB_API_KEY} environment variable."
            )
        self.__client = PLClient(secret=api_key)

    @staticmethod
    def __upscale_animation(animation_file_path: str, upscaled_animation_path: str):
        anmation_file_path_with_extension = image_path_with_extension(
            animation_file_path
        )
        img = imread(
            anmation_file_path_with_extension, IMREAD_UNCHANGED
        )  # keeps alpha if it exists
        upscaled = resize(img, (200, 200), interpolation=INTER_NEAREST)
        imwrite(upscaled_animation_path, upscaled)

    @staticmethod
    def __default_folder_path(maybe_folder_name: Optional[str] = None):
        folder_path: str = PixellabAnimator.__DEFAULT_FOLDER_BASE_PATH
        if maybe_folder_name is not None and len(maybe_folder_name) > 0:
            return f"{folder_path}/{maybe_folder_name}"
        else:
            return f"{folder_path}/{PixellabAnimator.__DEFAULT_FOLDER_NAME}"

    def generate_pixellab_animation(
        self,
        description: str,
        action: str,
        animations_save_folder: str,
        ref_image_path: str,
    ) -> PixellabAnimationResult:
        result: PixellabAnimationResult = PixellabAnimationResult()
        try:
            if len(ref_image_path) == 0:
                result.add_err(
                    f"Reference image not provided, unable to generate {action} animation."
                )
                return result
            if len(description) == 0:
                result.add_err(
                    f"Can't generate animations for anempty character description"
                )
                return result
            full_description: str = f"{self.__BASE_PROMPT}{description}"
            pixellab_ref_image: PILImage = pil_image_open(ref_image_path)
            # NOTE: The image needs to be scaled to 64x64 otherwise the request fails.
            pixellab_ref_image = pixellab_ref_image.resize((64, 64))
            response: AnimateWithTextResponse = animate_with_text(
                self.__client,
                description=full_description,
                action=action,
                view="side",
                direction="east",
                negative_description="No negative description",
                image_size=ImageSize(width=64, height=64),
                reference_image=pixellab_ref_image,
                n_frames=4,
            )
            animation_images: List[PILImage] = [
                image.pil_image() for image in response.images
            ]
            save_folder_64: str = new_folder(f"{animations_save_folder}/{action}_64")
            # NOTE: The upscaled version is the one intended to be used
            save_folder_upscaled: str = new_folder(f"{animations_save_folder}/{action}")
            for i, animation_img in enumerate(animation_images):
                # First save the animation frame as provided by pixellab, then upscale it and save the upscaled version.
                # This way we keep both the original and upscaled versions.

                animation_file_path_64: str = new_image_file_path(
                    f"{save_folder_64}/{action}_64x64_{i}"
                )
                animation_img.save(animation_file_path_64)
                upscaled_animation_path: str = new_image_file_path(
                    f"{save_folder_upscaled}/{action}_{i}"
                )
                self.__upscale_animation(
                    animation_file_path_64, upscaled_animation_path
                )
            result.action_folders[action] = save_folder_upscaled
        except Exception as e:
            result.add_err(
                f"An error ocurred when trying to generate {action} animation with pixellab: {e}"
            )
        return result

    def generate_animations(
        self, request: AnimationRequest, animations_folder: Optional[str] = None
    ) -> PixellabAnimationResult:
        result: PixellabAnimationResult = PixellabAnimationResult()
        aniumations_save_folder: str = ""
        if animations_folder is not None and len(animations_folder) > 0:
            aniumations_save_folder = animations_folder
        else:
            aniumations_save_folder = self.__default_folder_path(
                request.char_data.title
            )
        ref_image_path: Optional[str] = request.char_data.ref_image_path
        if ref_image_path is None or len(ref_image_path) == 0:
            result.add_err(
                "Reference image path not provided in the request, unable to generate animations."
            )
            return result
        for i, animation_action in enumerate(request.actions):
            if i > 0 and len(result.action_folders) > 0:
                # For consistency between animations of the same character, we use the reference image from the first generated animation for all the other subsequent animations.
                maybe_existing_animation_image: Optional[str] = (
                    find_first_image_in_folder(list(result.action_folders.values())[0])
                )
                if maybe_existing_animation_image is not None:
                    ref_image_path = maybe_existing_animation_image
                else:
                    result.add_err(
                        f"Reference image not found in previously generated animation folder, using original reference image for {animation_action} animation generation."
                    )
            result.combine_with(
                self.generate_pixellab_animation(
                    request.char_data.description,
                    animation_action,
                    aniumations_save_folder,
                    ref_image_path,
                )
            )
            # Adding a sleep between animation generations to avoid hitting pixellab rate limits in case of multiple animations requested.
            sleep(5)
        return result
