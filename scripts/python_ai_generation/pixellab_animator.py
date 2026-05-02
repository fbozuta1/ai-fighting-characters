from pixellab import Client as PLClient
from pixellab.animate_with_text import (
    AnimateWithTextResponse,
    ImageSize,
    animate_with_text,
)
from base64 import b64decode, b64encode
from io import BytesIO
from PIL.Image import Image as PILImage
from PIL.Image import open as pil_image_open
from typing import Any, Optional, List, Dict, Callable
from requests import get as requests_get
from requests import post as requests_post
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
    __api_key: str
    __animation_endpoint: str

    __BASE_PROMPT: str = (
        "Generate animation frames for the character provided in the image attachment. The character graphics and coloring remain the same in the attched reference image. Character description:"
    )

    __PIXELLAB_API_KEY: str = "PIXELLAB_API_KEY"
    __PIXELLAB_ANIMATION_ENDPOINT: str = "PIXELLAB_ANIMATION_ENDPOINT"
    __DEFAULT_FOLDER_BASE_PATH: str = "animation_frames"
    __DEFAULT_FOLDER_NAME: str = "ai_character"

    __BASE_URL: str = "https://api.pixellab.ai/v2"
    __ANIMATE_WITH_TEXT_V1: str = "animate-with-text"
    __ANIMATE_WITH_TEXT_V2: str = "animate-with-text-v2"
    __BACKGROUND_JOBS: str = "background-jobs"
    __DEFAULT_ANIMATION_ENDPOINT: str = __ANIMATE_WITH_TEXT_V1
    __V1_IMAGE_SIZE: int = 64
    __V2_IMAGE_SIZE: int = 256
    __V2_POLL_SECONDS: int = 5
    __V2_MAX_POLL_ATTEMPTS: int = 60

    def __init__(
        self,
    ):
        api_key: Optional[str] = environ.get(self.__PIXELLAB_API_KEY)
        if api_key is None:
            raise Exception(
                f"Api key not defined, please get an api key and set the {self.__PIXELLAB_API_KEY} environment variable."
            )
        self.__api_key = api_key
        self.__animation_endpoint = environ.get(
            self.__PIXELLAB_ANIMATION_ENDPOINT,
            self.__DEFAULT_ANIMATION_ENDPOINT,
        ).strip()
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

    @staticmethod
    def __image_to_base64_data_url(image: PILImage) -> str:
        image_bytes: BytesIO = BytesIO()
        image.save(image_bytes, format="PNG")
        encoded_image: str = b64encode(image_bytes.getvalue()).decode("utf-8")
        return f"data:image/png;base64,{encoded_image}"

    @staticmethod
    def __pil_image_from_base64(image_base64: str) -> PILImage:
        if "," in image_base64:
            image_base64 = image_base64.split(",", 1)[1]
        image_data: bytes = b64decode(image_base64)
        with pil_image_open(BytesIO(image_data)) as image:
            return image.copy()

    @staticmethod
    def __extract_base64_image(image_data: Any) -> Optional[str]:
        if isinstance(image_data, str):
            return image_data
        if not isinstance(image_data, dict):
            return None
        for key in ("base64", "b64_json", "image"):
            maybe_image: Optional[str] = image_data.get(key)
            if isinstance(maybe_image, str):
                return maybe_image
        return None

    @classmethod
    def __images_from_v2_response(cls, response_json: Any) -> List[PILImage]:
        if isinstance(response_json, dict):
            raw_images: Any = response_json.get("images")
            if raw_images is None:
                raw_images = response_json.get("image")
            if raw_images is None:
                for wrapper_key in ("data", "result", "output", "response"):
                    wrapped_response: Any = response_json.get(wrapper_key)
                    if wrapped_response is not None:
                        try:
                            return cls.__images_from_v2_response(wrapped_response)
                        except Exception:
                            pass
        else:
            raw_images = response_json

        if raw_images is None:
            response_keys: str = ""
            if isinstance(response_json, dict):
                response_keys = f" Top-level keys: {list(response_json.keys())}."
            response_preview: str = str(response_json)[:500]
            raise Exception(
                "Pixellab v2 response did not include image data."
                f"{response_keys} Response preview: {response_preview}"
            )
        if not isinstance(raw_images, list):
            raw_images = [raw_images]

        animation_images: List[PILImage] = []
        for raw_image in raw_images:
            maybe_image_base64: Optional[str] = cls.__extract_base64_image(raw_image)
            if maybe_image_base64 is None:
                raise Exception(f"Unsupported image response format: {raw_image}")
            animation_images.append(cls.__pil_image_from_base64(maybe_image_base64))

        return cls.__split_frame_sheets(animation_images)

    @staticmethod
    def __split_frame_sheets(images: List[PILImage]) -> List[PILImage]:
        frame_size: int = PixellabAnimator.__V2_IMAGE_SIZE
        frames: List[PILImage] = []
        for image in images:
            width, height = image.size
            if width <= frame_size and height <= frame_size:
                frames.append(image)
                continue
            if width % frame_size != 0 or height % frame_size != 0:
                frames.append(image)
                continue
            for top in range(0, height, frame_size):
                for left in range(0, width, frame_size):
                    frames.append(
                        image.crop((left, top, left + frame_size, top + frame_size))
                    )
        return frames

    def __generate_animation_images_v1(
        self,
        description: str,
        action: str,
        reference_image: PILImage,
    ) -> List[PILImage]:
        full_description: str = f"{self.__BASE_PROMPT}{description}"
        response: AnimateWithTextResponse = animate_with_text(
            self.__client,
            description=full_description,
            action=action,
            view="side",
            direction="east",
            negative_description="No negative description",
            image_size=ImageSize(
                width=self.__V1_IMAGE_SIZE,
                height=self.__V1_IMAGE_SIZE,
            ),
            reference_image=reference_image,
            n_frames=4,
            seed=42,
        )
        return [image.pil_image() for image in response.images]

    def __generate_animation_images_v2(
        self,
        action: str,
        reference_image: PILImage,
    ) -> List[PILImage]:
        request_body: Dict[str, Any] = {
            "action": action,
            "direction": "east",
            "image_size": {
                "height": self.__V2_IMAGE_SIZE,
                "width": self.__V2_IMAGE_SIZE,
            },
            "no_background": True,
            "reference_image": {
                "base64": self.__image_to_base64_data_url(reference_image),
            },
            "reference_image_size": {
                "height": self.__V2_IMAGE_SIZE,
                "width": self.__V2_IMAGE_SIZE,
            },
            "seed": 42,
            "view": "side",
        }
        response = requests_post(
            f"{self.__BASE_URL}/{self.__ANIMATE_WITH_TEXT_V2}",
            headers={
                "Authorization": f"Bearer {self.__api_key}",
                "Content-Type": "application/json",
            },
            json=request_body,
            timeout=120,
        )
        response.raise_for_status()
        response_json: Any = response.json()
        job_id: Optional[str] = self.__background_job_id_from_response(response_json)
        if job_id is None:
            return self.__images_from_v2_response(response_json)
        return self.__poll_animation_images_v2(job_id)

    @staticmethod
    def __background_job_id_from_response(response_json: Any) -> Optional[str]:
        if not isinstance(response_json, dict):
            return None
        maybe_job_id: Any = response_json.get("background_job_id")
        if isinstance(maybe_job_id, str) and len(maybe_job_id) > 0:
            return maybe_job_id
        return None

    def __poll_animation_images_v2(self, job_id: str) -> List[PILImage]:
        for _ in range(self.__V2_MAX_POLL_ATTEMPTS):
            sleep(self.__V2_POLL_SECONDS)
            response = requests_get(
                f"{self.__BASE_URL}/{self.__BACKGROUND_JOBS}/{job_id}",
                headers={
                    "Authorization": f"Bearer {self.__api_key}",
                    "Content-Type": "application/json",
                },
                timeout=120,
            )
            response.raise_for_status()
            response_json: Any = response.json()
            if not isinstance(response_json, dict):
                raise Exception(
                    f"Unexpected Pixellab v2 background job response: {response_json}"
                )
            status: str = str(response_json.get("status", "")).lower()

            if status in ("completed", "complete", "succeeded", "success", "done"):
                last_response: Any = response_json.get("last_response")
                if last_response is None:
                    return self.__images_from_v2_response(response_json)
                return self.__images_from_v2_response(last_response)
            if status in ("failed", "error", "cancelled", "canceled"):
                raise Exception(
                    f"Pixellab v2 background job {job_id} failed: {response_json}"
                )

        raise Exception(
            f"Pixellab v2 background job {job_id} did not complete after "
            f"{self.__V2_MAX_POLL_ATTEMPTS * self.__V2_POLL_SECONDS} seconds"
        )

    def __reference_image_size(self) -> int:
        endpoint: str = self.__animation_endpoint.lower()
        if endpoint in ("v2", self.__ANIMATE_WITH_TEXT_V2):
            return self.__V2_IMAGE_SIZE
        return self.__V1_IMAGE_SIZE

    def __should_upscale_animation(self) -> bool:
        endpoint: str = self.__animation_endpoint.lower()
        return endpoint not in ("v2", self.__ANIMATE_WITH_TEXT_V2)

    def __generate_animation_images(
        self,
        description: str,
        action: str,
        reference_image: PILImage,
    ) -> List[PILImage]:
        endpoint: str = self.__animation_endpoint.lower()
        if endpoint in ("v1", self.__ANIMATE_WITH_TEXT_V1):
            return self.__generate_animation_images_v1(
                description,
                action,
                reference_image,
            )
        if endpoint in ("v2", self.__ANIMATE_WITH_TEXT_V2):
            return self.__generate_animation_images_v2(action, reference_image)
        raise Exception(
            f"Unknown Pixellab animation endpoint '{self.__animation_endpoint}'. "
            f"Use '{self.__ANIMATE_WITH_TEXT_V1}' or '{self.__ANIMATE_WITH_TEXT_V2}'."
        )

    def generate_pixellab_animation(
        self,
        description: str,
        action: str,
        animations_save_folder: str,
        ref_image_path: str,
        action_description: Optional[str] = None,
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
            pixellab_ref_image: PILImage = pil_image_open(ref_image_path)
            reference_image_size: int = self.__reference_image_size()
            pixellab_ref_image = pixellab_ref_image.resize(
                (reference_image_size, reference_image_size)
            )
            animation_images: List[PILImage] = self.__generate_animation_images(
                description,
                action=action_description or action,
                reference_image=pixellab_ref_image,
            )
            save_folder_original: str = new_folder(
                f"{animations_save_folder}/{action}_{reference_image_size}"
            )
            save_folder_upscaled: str = new_folder(f"{animations_save_folder}/{action}")
            for i, animation_img in enumerate(animation_images):
                animation_file_path_original: str = new_image_file_path(
                    f"{save_folder_original}/{action}_{reference_image_size}x{reference_image_size}_{i}"
                )
                animation_img.save(animation_file_path_original)
                upscaled_animation_path: str = new_image_file_path(
                    f"{save_folder_upscaled}/{action}_{i}"
                )
                if self.__should_upscale_animation():
                    self.__upscale_animation(
                        animation_file_path_original, upscaled_animation_path
                    )
                else:
                    animation_img.save(upscaled_animation_path)
            result.action_folders[action] = save_folder_upscaled
        except Exception as e:
            result.add_err(
                f"An error ocurred when trying to generate {action} animation with pixellab: {e}"
            )
        return result

    def generate_animations(
        self,
        request: AnimationRequest,
        animations_folder: Optional[str] = None,
        progress_callback: Optional[Callable[[str, int, int], None]] = None,
        action_descriptions: Optional[Dict[str, str]] = None,
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
        total_actions: int = len(request.actions)
        for i, animation_action in enumerate(request.actions):
            if progress_callback is not None:
                progress_callback(animation_action, i, total_actions)
            if i > 0 and len(result.action_folders) > 0:
                # For consistency between animations of the same character, we use the reference image from the first generated animation for all the other subsequent animations.
                #maybe_existing_animation_image: Optional[str] = (
                #    find_first_image_in_folder(list(result.action_folders.values())[0])
                #)
                #if maybe_existing_animation_image is not None:
                    #ref_image_path = maybe_existing_animation_image
                #else:
                #    result.add_err(
                #        f"Reference image not found in previously generated animation folder, using original reference image for {animation_action} animation generation."
                #    )
                pass
            result.combine_with(
                self.generate_pixellab_animation(
                    request.char_data.description,
                    animation_action,
                    aniumations_save_folder,
                    ref_image_path,
                    (
                        action_descriptions.get(animation_action)
                        if action_descriptions is not None
                        else None
                    ),
                )
            )
            # Adding a sleep between animation generations to avoid hitting pixellab rate limits in case of multiple animations requested.
            sleep(5)
        return result
