from openai import OpenAI
from openai.types import ImagesResponse
from typing import Optional, List
from base64 import b64decode
from utils import new_image_file_path
from dataclasses import dataclass, field


@dataclass
class PixelArtResult:
    gen_image_path: Optional[str] = None
    errors: List[str] = field(default_factory=list)

    def add_err(self, err: str):
        self.errors.append(err)


class OpenAIPixelArtGenerator:
    __base_prompt: str
    __client: OpenAI
    __model: str

    __DEFAULT_MODEL: str = "gpt-image-1"
    __DEFAULT_IMAGE_NAME: str = "open_ai_image"
    __BASE_PROMPT_FILE: str = "prompt.txt"
    __DEFAULT_PROMPT: str = (
        "Generate 2d pixel art animation for a gaming character sprite. The character is in idling state and is facing east:\n"
    )

    def __init__(self, model: str = __DEFAULT_MODEL):
        self.__model = model
        self.__client = OpenAI()
        self.__load_prompt_from_file()

    def __load_prompt_from_file(self):
        try:
            with open(self.__BASE_PROMPT_FILE, "r") as prompt_file:
                self.__base_prompt = prompt_file.read()
        except Exception as e:
            print(
                f"Warning: error when loading prompt from file {self.__BASE_PROMPT_FILE}:{e}\nUsing default prompt:\n{self.__DEFAULT_PROMPT}."
            )
            self.__base_prompt = self.__DEFAULT_PROMPT

    def set_model(self, model: str):
        self.__model = model

    @staticmethod
    def __write_image_file(image_file_name: str, image_bytes: bytes) -> Optional[str]:
        image_path: str = new_image_file_path(image_file_name)
        with open(image_path, "wb") as image_file:
            image_file.write(image_bytes)
        return str(image_path)

    # Returns a path to the saved image if all was good
    def generate_pixel_art_character(
        self, char_description: str, image_save_path: str
    ) -> PixelArtResult:
        result: PixelArtResult = PixelArtResult()
        try:
            if len(char_description) == 0:
                result.add_err("Character description is empty.")
                return result
            full_prompt: str = f"{self.__base_prompt}{char_description}"
            response: ImagesResponse = self.__client.images.generate(
                model=self.__model,
                prompt=full_prompt,
            )
            image_base64: Optional[str] = response.data[0].b64_json
            if image_base64 is None or len(image_base64) == 0:
                result.add_err("No image data in the response")
                return result
            image_bytes: bytes = b64decode(image_base64)
            if len(image_save_path) == 0:
                image_save_path = self.__DEFAULT_IMAGE_NAME
            image_file_path: str = self.__write_image_file(image_save_path, image_bytes)
            result.gen_image_path = image_file_path
            return result
        except Exception as e:
            result.add_err(f"Error when generating open ai image: {e}")
            return result
