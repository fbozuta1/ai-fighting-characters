from dataclasses import dataclass, asdict, field
from dacite import from_dict
from json import dump as json_dump
from json import load as json_load
from typing import Optional, List, Dict
from pathlib import Path
from utils import new_json_file_path, json_file_path
from copy import deepcopy


@dataclass
class CharacterData:
    title: str = ""
    description: str = ""
    ref_image_path: Optional[str] = None


@dataclass
class AnimationRequest:
    char_data: CharacterData
    actions: List[str]
    base_folder: str


@dataclass
class RequestLoadResult:
    request: Optional[AnimationRequest] = None
    errors: List[str] = field(default_factory=list)


def load_request_from_file(req_file_path: str) -> RequestLoadResult:
    load_result: RequestLoadResult = RequestLoadResult()
    try:
        file_path: Path = Path(json_file_path(req_file_path))
        if not file_path.is_file():
            load_result.errors.append(
                f"File at path {req_file_path} doesn't exist to read animation data"
            )
            return load_result
        with open(file_path) as request_file:
            request: AnimationRequest = from_dict(
                AnimationRequest, json_load(request_file)
            )
            load_result.request = request
        return load_result
    except Exception as e:
        load_result.errors.append(f"Error when reading animation data: {str(e)}")
        return load_result


@dataclass
class AnimationResult:
    char_data: Optional[CharacterData] = None
    action_folders: Dict[str, str] = field(default_factory=dict)
    result_folder: Optional[str] = None
    errors: List[str] = field(default_factory=list)

    __DEFAULT_SAVE_PATH: str = "animation_result"

    def add_err(self, err: str):
        self.errors.append(err)

    def read_data_from_req_load_result(self, request_load_result: RequestLoadResult):
        self.errors.extend(request_load_result.errors)
        if request_load_result.request is not None:
            self.char_data = deepcopy(request_load_result.request.char_data)
        else:
            self.add_err("Failed to read request.")

    def save_to_file(self, save_path: Optional[str] = None) -> Optional[str]:
        try:
            result_path_str: str = (
                save_path if save_path is not None else self.__DEFAULT_SAVE_PATH
            )
            result_path_resolved = new_json_file_path(result_path_str)
            result_file_path: Path = Path(result_path_resolved)
            result_file_path.parent.mkdir(parents=True, exist_ok=True)
            with open(result_file_path, "w") as result_file:
                json_dump(asdict(self), result_file)
            return result_file_path
        except Exception as e:
            print(f"Error when saving animation result: {str(e)}")
            return None
