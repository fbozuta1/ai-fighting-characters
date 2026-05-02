from dataclasses import dataclass, field
from json import loads as json_loads
from os import environ
from typing import Dict, List, Optional

from openai import OpenAI


@dataclass
class ActionDescriptionResult:
    action_descriptions: Dict[str, str] = field(default_factory=dict)
    errors: List[str] = field(default_factory=list)

    def add_err(self, err: str):
        self.errors.append(err)


class OpenAIActionDescriptionGenerator:
    __client: OpenAI
    __model: str

    __DEFAULT_MODEL: str = "gpt-4.1-mini"
    __MODEL_ENV_VAR: str = "OPENAI_ACTION_DESCRIPTION_MODEL"

    def __init__(self, model: Optional[str] = None):
        self.__model = model or environ.get(
            self.__MODEL_ENV_VAR,
            self.__DEFAULT_MODEL,
        )
        self.__client = OpenAI()

    @staticmethod
    def __prompt(character_description: str, actions: List[str]) -> str:
        actions_list: str = ", ".join(actions)
        return (
            "Create concise animation action prompts for a pixel-art fighting game character.\n"
            "Return only valid JSON, with each requested action as a key and a detailed action description as the value.\n"
            "Each value should be one sentence, 12-28 words, clear for an image animation model.\n"
            "Keep the character's existing costume, weapon, colors, proportions, and side-view facing-east orientation.\n"
            "Do not add new weapons, characters, effects, backgrounds, camera moves, or UI.\n"
            "Make idle subtle, walk readable as a loop, and fight/attack decisive but still sprite-friendly.\n\n"
            f"Character description: {character_description}\n"
            f"Actions: {actions_list}\n"
        )

    @staticmethod
    def __response_text(response) -> str:
        maybe_output_text: Optional[str] = getattr(response, "output_text", None)
        if maybe_output_text is not None and len(maybe_output_text) > 0:
            return maybe_output_text
        return response.choices[0].message.content

    @staticmethod
    def __clean_json_response(response_text: str) -> str:
        response_text = response_text.strip()
        if not response_text.startswith("```"):
            return response_text
        lines: List[str] = response_text.splitlines()
        if len(lines) >= 3:
            return "\n".join(lines[1:-1]).strip()
        return response_text

    def generate_action_descriptions(
        self,
        character_description: str,
        actions: List[str],
    ) -> ActionDescriptionResult:
        result: ActionDescriptionResult = ActionDescriptionResult()
        try:
            if len(character_description) == 0:
                result.add_err("Character description is empty.")
                return result
            if len(actions) == 0:
                result.add_err("No animation actions provided.")
                return result

            prompt: str = self.__prompt(character_description, actions)
            try:
                response = self.__client.responses.create(
                    model=self.__model,
                    input=prompt,
                    temperature=0.3,
                )
            except AttributeError:
                response = self.__client.chat.completions.create(
                    model=self.__model,
                    messages=[
                        {
                            "role": "system",
                            "content": "You return only valid JSON.",
                        },
                        {
                            "role": "user",
                            "content": prompt,
                        },
                    ],
                    temperature=0.3,
                )

            response_text: str = self.__clean_json_response(
                self.__response_text(response)
            )
            parsed_descriptions = json_loads(response_text)
            if not isinstance(parsed_descriptions, dict):
                result.add_err("OpenAI action description response was not a JSON object.")
                return result

            for action in actions:
                maybe_description = parsed_descriptions.get(action)
                if isinstance(maybe_description, str) and len(maybe_description) > 0:
                    result.action_descriptions[action] = maybe_description

            missing_actions: List[str] = [
                action for action in actions if action not in result.action_descriptions
            ]
            if len(missing_actions) > 0:
                result.add_err(
                    f"OpenAI action description response missed actions: {missing_actions}"
                )
            return result
        except Exception as e:
            result.add_err(f"Error when generating OpenAI action descriptions: {e}")
            return result
