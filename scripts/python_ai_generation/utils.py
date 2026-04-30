from pathlib import Path
from os import makedirs, listdir, path as os_path
from typing import Optional

DEFAULT_IMAGE_EXTENSION: str = "png"
JSON_EXTENSION: str = "json"


def new_folder(folder_path_str: str) -> str:
    """
    Creates a new folder at the specified path.
    If a folder with the same name already exists,
    it appends an index to the folder name until an available name is found.
    """
    folder_path: Path = Path(folder_path_str)
    i: int = 0
    while folder_path.exists() and folder_path.is_dir():
        folder_path = Path(f"{folder_path}_{i}")
        i += 1
    makedirs(folder_path, exist_ok=True)
    return str(folder_path)


def file_path_without_extension(
    image_file_path: str, extension: str = DEFAULT_IMAGE_EXTENSION
) -> str:
    """Removes the specified extension from the file path if it's present."""
    if image_file_path.endswith(f".{extension}"):
        return str(Path(image_file_path).with_suffix(""))
    return image_file_path


def image_path_without_extension(
    image_file_path: str, extension: str = DEFAULT_IMAGE_EXTENSION
) -> str:
    """Removes the specified extension from the image file path if it's present."""
    return file_path_without_extension(image_file_path, extension)


def file_path_with_extension(file_path: str, extension: str) -> str:
    """
    Ensures that the provided file path has the specified extension.
    If the file path already ends with the extension, it is returned unchanged.
    Otherwise, the extension is appended to the file path.
    """
    return (
        file_path if file_path.endswith(f".{extension}") else f"{file_path}.{extension}"
    )


def image_path_with_extension(
    image_file_path: str, extension: str = DEFAULT_IMAGE_EXTENSION
) -> str:
    """
    Ensures that the provided image file path has the specified extension.
    If the file path already ends with the extension, it is returned unchanged.
    Otherwise, the extension is appended to the file path.
    If no extension is provided, it defaults to the ".png" extension.
    """
    return file_path_with_extension(image_file_path, extension)


def json_file_path(json_file_path: str) -> str:
    """
    Ensures that the provided JSON file path has the ".json" extension.
    """
    return file_path_with_extension(json_file_path, JSON_EXTENSION)


def new_file_path(file_path_str: str, extension: str) -> str:
    """
    Returns a new file path that does not conflict with existing files.
    It also ensures the extensions is correct.
    """
    available_path: Path = Path(file_path_with_extension(file_path_str, extension))
    path_name_without_extension: str = file_path_without_extension(
        file_path_str, extension
    )
    i: int = 0
    while available_path.exists() and available_path.is_file():
        available_path = Path(f"{path_name_without_extension}_{i}.{extension}")
        i += 1
    return str(available_path)


def new_json_file_path(json_file_path_str: str) -> str:
    """
    Returns a new JSON file path that does not conflict with existing files.
    """
    return new_file_path(json_file_path_str, JSON_EXTENSION)


def new_image_file_path(
    image_file_path: str, extension: str = DEFAULT_IMAGE_EXTENSION
) -> str:
    """
    Returns a new image file path that does not conflict with existing files.
    It also ensures the extensions is correct.
    """
    return new_file_path(image_file_path, extension)


def find_first_image_in_folder(
    folder_path: str, extension: str = DEFAULT_IMAGE_EXTENSION
) -> Optional[str]:
    for filename in listdir(folder_path):
        if filename.lower().endswith(f".{extension}"):
            return os_path.join(folder_path, filename)
    return None
