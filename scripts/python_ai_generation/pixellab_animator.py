from pixellab import Client as PLClient
from pixellab.animate_with_text import (
    AnimateWithTextResponse,
    ImageSize,
    animate_with_text,
)
from pixellab.estimate_skeleton import estimate_skeleton
from base64 import b64decode, b64encode
from copy import deepcopy
from io import BytesIO
from json import dump as json_dump
from math import pi, sin
from PIL.Image import Image as PILImage
from PIL.Image import open as pil_image_open
from typing import Any, Optional, List, Dict, Callable
from requests import get as requests_get
from requests import post as requests_post
from cv2 import imread, resize, imwrite, IMREAD_UNCHANGED, INTER_NEAREST
from utils import (
    new_folder,
    new_image_file_path,
    new_json_file_path,
    image_path_with_extension,
    find_first_image_in_folder,
    sanitize_error_message,
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
    __ANIMATE_WITH_SKELETON: str = "animate-with-skeleton"
    __BACKGROUND_JOBS: str = "background-jobs"
    __DEFAULT_ANIMATION_ENDPOINT: str = __ANIMATE_WITH_SKELETON
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
    def __image_to_base64_image_payload(image: PILImage) -> Dict[str, str]:
        image_bytes: BytesIO = BytesIO()
        image.save(image_bytes, format="PNG")
        encoded_image: str = b64encode(image_bytes.getvalue()).decode("utf-8")
        return {
            "type": "base64",
            "base64": encoded_image,
            "format": "png",
        }

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

    @staticmethod
    def __copy_keypoint(keypoint: Any) -> Dict[str, Any]:
        return dict(keypoint)

    @classmethod
    def __translated_keypoints(
        cls,
        keypoints: List[Any],
        labels: List[str],
        dx: float = 0.0,
        dy: float = 0.0,
    ) -> List[Dict[str, Any]]:
        translated_keypoints: List[Dict[str, Any]] = []
        labels_set = set(labels)
        for keypoint in keypoints:
            copied_keypoint: Dict[str, Any] = cls.__copy_keypoint(keypoint)
            if copied_keypoint.get("label") in labels_set:
                copied_keypoint["x"] = float(copied_keypoint.get("x", 0.0)) + dx
                copied_keypoint["y"] = float(copied_keypoint.get("y", 0.0)) + dy
            translated_keypoints.append(copied_keypoint)
        return translated_keypoints

    @classmethod
    def __idle_skeleton_frames(
        cls,
        base_keypoints: List[Any],
        frame_count: int = 4,
    ) -> List[List[Dict[str, Any]]]:
        head_labels: List[str] = [
            "NOSE",
            "LEFT EYE",
            "RIGHT EYE",
            "LEFT EAR",
            "RIGHT EAR",
        ]
        torso_labels: List[str] = [
            "NECK",
            "LEFT SHOULDER",
            "RIGHT SHOULDER",
            "LEFT HIP",
            "RIGHT HIP",
        ]
        arm_labels: List[str] = ["LEFT ELBOW", "LEFT ARM", "RIGHT ELBOW", "RIGHT ARM"]
        frames: List[List[Dict[str, Any]]] = []
        for frame_index in range(frame_count):
            phase: float = (frame_index / frame_count) * 2 * pi
            bob: float = sin(phase) * 0.008
            frame_keypoints: List[Dict[str, Any]] = deepcopy(base_keypoints)
            frame_keypoints = cls.__translated_keypoints(
                frame_keypoints,
                head_labels,
                dy=bob * 1.2,
            )
            frame_keypoints = cls.__translated_keypoints(
                frame_keypoints,
                torso_labels,
                dy=bob,
            )
            frame_keypoints = cls.__translated_keypoints(
                frame_keypoints,
                arm_labels,
                dy=bob * 0.7,
            )
            frames.append(frame_keypoints)
        return frames

    @classmethod
    def __walk_skeleton_frames(
        cls,
        base_keypoints: List[Any],
        frame_count: int = 6,
    ) -> List[List[Dict[str, Any]]]:
        frames: List[List[Dict[str, Any]]] = []
        for frame_index in range(frame_count):
            phase: float = (frame_index / frame_count) * 2 * pi
            body_bob: float = abs(sin(phase)) * -0.008
            left_leg_swing: float = sin(phase)
            right_leg_swing: float = sin(phase + pi)
            left_arm_swing: float = sin(phase + pi)
            right_arm_swing: float = sin(phase)

            frame_keypoints: List[Dict[str, Any]] = deepcopy(base_keypoints)
            frame_keypoints = cls.__translated_keypoints(
                frame_keypoints,
                [
                    "NOSE",
                    "NECK",
                    "LEFT SHOULDER",
                    "RIGHT SHOULDER",
                    "LEFT HIP",
                    "RIGHT HIP",
                ],
                dy=body_bob,
            )
            frame_keypoints = cls.__translated_keypoints(
                frame_keypoints,
                ["LEFT ELBOW", "LEFT ARM"],
                dx=left_arm_swing * 0.016,
                dy=abs(left_arm_swing) * 0.006,
            )
            frame_keypoints = cls.__translated_keypoints(
                frame_keypoints,
                ["RIGHT ELBOW", "RIGHT ARM"],
                dx=right_arm_swing * 0.016,
                dy=abs(right_arm_swing) * 0.006,
            )
            frame_keypoints = cls.__translated_keypoints(
                frame_keypoints,
                ["LEFT KNEE"],
                dx=left_leg_swing * 0.016,
                dy=-max(0.0, left_leg_swing) * 0.012,
            )
            frame_keypoints = cls.__translated_keypoints(
                frame_keypoints,
                ["LEFT LEG"],
                dx=left_leg_swing * 0.032,
                dy=-max(0.0, left_leg_swing) * 0.016,
            )
            frame_keypoints = cls.__translated_keypoints(
                frame_keypoints,
                ["RIGHT KNEE"],
                dx=right_leg_swing * 0.016,
                dy=-max(0.0, right_leg_swing) * 0.012,
            )
            frame_keypoints = cls.__translated_keypoints(
                frame_keypoints,
                ["RIGHT LEG"],
                dx=right_leg_swing * 0.032,
                dy=-max(0.0, right_leg_swing) * 0.016,
            )
            frames.append(frame_keypoints)
        return frames

    @classmethod
    def __procedural_skeleton_frames(
        cls,
        action: str,
        base_keypoints: List[Any],
    ) -> List[List[Dict[str, Any]]]:
        action_lower: str = action.lower()
        if "walk" in action_lower or "run" in action_lower:
            return cls.__walk_skeleton_frames(base_keypoints)
        return cls.__idle_skeleton_frames(base_keypoints)

    @staticmethod
    def __save_skeleton_debug_json(
        debug_folder: str,
        action: str,
        neutral_keypoints: List[Any],
        skeleton_frames: List[List[Dict[str, Any]]],
    ) -> None:
        skeleton_json_path: str = new_json_file_path(
            f"{debug_folder}/{action}_skeleton_keypoints"
        )
        with open(skeleton_json_path, "w") as skeleton_json_file:
            json_dump(
                {
                    "neutral_keypoints": neutral_keypoints,
                    "skeleton_keypoints": skeleton_frames,
                },
                skeleton_json_file,
                indent=2,
            )

    @staticmethod
    def __save_skeleton_request_debug_json(
        debug_folder: str,
        action: str,
        request_body: Dict[str, Any],
    ) -> None:
        debug_request_body: Dict[str, Any] = deepcopy(request_body)
        reference_image: Any = debug_request_body.get("reference_image")
        if isinstance(reference_image, dict) and "base64" in reference_image:
            reference_image["base64"] = (
                f"[base64 image omitted, {len(reference_image['base64'])} chars]"
            )
        request_json_path: str = new_json_file_path(
            f"{debug_folder}/{action}_animate_with_skeleton_request"
        )
        with open(request_json_path, "w") as request_json_file:
            json_dump(debug_request_body, request_json_file, indent=2)

    @staticmethod
    def __raise_for_status_with_body(response: Any) -> None:
        try:
            response.raise_for_status()
        except Exception as error:
            response_body: str = ""
            try:
                response_body = response.text
            except Exception:
                response_body = ""
            if len(response_body) == 0:
                try:
                    response_body = str(response.json())
                except Exception:
                    response_body = ""
            if len(response_body) > 0:
                raise Exception(f"{error}. Response body: {response_body}") from error
            raise

    def __generate_animation_images_with_skeleton(
        self,
        action: str,
        reference_image: PILImage,
        debug_folder: str,
    ) -> List[PILImage]:
        estimated_skeleton = estimate_skeleton(
            self.__client,
            reference_image,
        )
        neutral_keypoints: List[Any] = [
            self.__copy_keypoint(keypoint) for keypoint in estimated_skeleton.keypoints
        ]
        skeleton_frames: List[List[Dict[str, Any]]] = self.__procedural_skeleton_frames(
            action,
            neutral_keypoints,
        )
        self.__save_skeleton_debug_json(
            debug_folder,
            action,
            neutral_keypoints,
            skeleton_frames,
        )
        request_body: Dict[str, Any] = {
            "image_size": {
                "height": self.__V2_IMAGE_SIZE,
                "width": self.__V2_IMAGE_SIZE,
            },
            "skeleton_keypoints": skeleton_frames,
            "view": "side",
            "direction": "east",
            "reference_guidance_scale": 1.1,
            "pose_guidance_scale": 3.0,
            "reference_image": self.__image_to_base64_image_payload(reference_image),
            "seed": 42,
        }
        self.__save_skeleton_request_debug_json(
            debug_folder,
            action,
            request_body,
        )
        response = requests_post(
            f"{self.__BASE_URL}/{self.__ANIMATE_WITH_SKELETON}",
            headers={
                "Authorization": f"Bearer {self.__api_key}",
                "Content-Type": "application/json",
            },
            json=request_body,
            timeout=120,
        )
        self.__raise_for_status_with_body(response)
        return self.__images_from_v2_response(response.json())

    def __reference_image_size(self) -> int:
        endpoint: str = self.__animation_endpoint.lower()
        if endpoint in (
            "v2",
            self.__ANIMATE_WITH_TEXT_V2,
            "skeleton",
            self.__ANIMATE_WITH_SKELETON,
        ):
            return self.__V2_IMAGE_SIZE
        return self.__V1_IMAGE_SIZE

    def __should_upscale_animation(self) -> bool:
        endpoint: str = self.__animation_endpoint.lower()
        return endpoint not in (
            "v2",
            self.__ANIMATE_WITH_TEXT_V2,
            "skeleton",
            self.__ANIMATE_WITH_SKELETON,
        )

    def __generate_animation_images(
        self,
        description: str,
        action: str,
        reference_image: PILImage,
        debug_folder: str,
        action_description: Optional[str] = None,
    ) -> List[PILImage]:
        endpoint: str = self.__animation_endpoint.lower()
        pixellab_action: str = action_description or action
        if endpoint in ("v1", self.__ANIMATE_WITH_TEXT_V1):
            return self.__generate_animation_images_v1(
                description,
                pixellab_action,
                reference_image,
            )
        if endpoint in ("v2", self.__ANIMATE_WITH_TEXT_V2):
            return self.__generate_animation_images_v2(
                pixellab_action,
                reference_image,
            )
        if endpoint in ("skeleton", self.__ANIMATE_WITH_SKELETON):
            return self.__generate_animation_images_with_skeleton(
                action,
                reference_image,
                debug_folder,
            )
        raise Exception(
            f"Unknown Pixellab animation endpoint '{self.__animation_endpoint}'. "
            f"Use '{self.__ANIMATE_WITH_TEXT_V1}', '{self.__ANIMATE_WITH_TEXT_V2}', "
            f"or '{self.__ANIMATE_WITH_SKELETON}'."
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
            save_folder_original: str = new_folder(
                f"{animations_save_folder}/{action}_{reference_image_size}"
            )
            save_folder_upscaled: str = new_folder(f"{animations_save_folder}/{action}")
            animation_images: List[PILImage] = self.__generate_animation_images(
                description,
                action=action,
                reference_image=pixellab_ref_image,
                debug_folder=save_folder_original,
                action_description=action_description,
            )
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
                f"An error ocurred when trying to generate {action} animation with pixellab: {sanitize_error_message(e)}"
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
