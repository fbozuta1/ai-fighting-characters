import base64
import json
import os
import sys
import tempfile
import types
import unittest
from pathlib import Path
from unittest.mock import MagicMock, patch

# Ensure missing third-party modules are stubbed for import-time safety.
if "openai" not in sys.modules:
    openai_mod = types.ModuleType("openai")
    openai_mod.OpenAI = MagicMock
    sys.modules["openai"] = openai_mod

if "openai.types" not in sys.modules:
    openai_types = types.ModuleType("openai.types")
    openai_types.ImagesResponse = object
    sys.modules["openai.types"] = openai_types

if "pixellab" not in sys.modules:
    pixellab_mod = types.ModuleType("pixellab")
    pixellab_mod.Client = MagicMock
    sys.modules["pixellab"] = pixellab_mod

if "pixellab.animate_with_text" not in sys.modules:
    animate_mod = types.ModuleType("pixellab.animate_with_text")
    animate_mod.AnimateWithTextResponse = object
    animate_mod.ImageSize = MagicMock
    animate_mod.animate_with_text = MagicMock()
    sys.modules["pixellab.animate_with_text"] = animate_mod

import open_ai_pixel_art
import pixellab_animator
import pixellab_generation_script
from data_format import AnimationRequest, CharacterData, AnimationResult
from pixellab_animator import PixellabAnimationResult
from open_ai_pixel_art import PixelArtResult


class TestOpenAIPixelArtGenerator(unittest.TestCase):
    def test_generate_pixel_art_character_empty_description(self):
        generator = open_ai_pixel_art.OpenAIPixelArtGenerator()
        result = generator.generate_pixel_art_character("", "output_path")

        self.assertIsNone(result.gen_image_path)
        self.assertEqual(result.errors, ["Character description is empty."])

    @patch("open_ai_pixel_art.OpenAI")
    @patch("open_ai_pixel_art.new_image_file_path")
    def test_generate_pixel_art_character_success(
        self, mock_new_image_file_path, mock_openai_class
    ):
        fake_bytes = b"not-a-real-image"
        fake_base64 = base64.b64encode(fake_bytes).decode("utf-8")
        fake_response = MagicMock()
        fake_response.data = [MagicMock(b64_json=fake_base64)]

        fake_client = MagicMock()
        fake_client.images.generate.return_value = fake_response
        mock_openai_class.return_value = fake_client

        with tempfile.TemporaryDirectory() as temp_dir:
            temp_path = Path(temp_dir) / "generated.png"
            mock_new_image_file_path.return_value = str(temp_path)

            generator = open_ai_pixel_art.OpenAIPixelArtGenerator()
            result = generator.generate_pixel_art_character("A pixel hero", "generated")

            self.assertEqual(result.errors, [])
            self.assertEqual(result.gen_image_path, str(temp_path))
            self.assertTrue(temp_path.exists())
            self.assertEqual(temp_path.read_bytes(), fake_bytes)

    @patch("open_ai_pixel_art.OpenAI")
    def test_generate_pixel_art_character_no_image_data(self, mock_openai_class):
        fake_response = MagicMock()
        fake_response.data = [MagicMock(b64_json=None)]

        fake_client = MagicMock()
        fake_client.images.generate.return_value = fake_response
        mock_openai_class.return_value = fake_client

        generator = open_ai_pixel_art.OpenAIPixelArtGenerator()
        result = generator.generate_pixel_art_character("A pixel hero", "generated")

        self.assertIsNone(result.gen_image_path)
        self.assertEqual(result.errors, ["No image data in the response"])


class TestPixellabAnimator(unittest.TestCase):
    def setUp(self):
        self.patcher_env = patch.dict(os.environ, {"PIXELLAB_API_KEY": "test-key"})
        self.patcher_env.start()
        self.addCleanup(self.patcher_env.stop)

    @patch("pixellab_animator.PLClient")
    def test_generate_pixellab_animation_missing_ref_image(self, mock_pl_client):
        animator = pixellab_animator.PixellabAnimator()
        result = animator.generate_pixellab_animation(
            "A hero",
            "walk",
            "animations",
            "",
        )

        self.assertEqual(result.action_folders, {})
        self.assertEqual(
            result.errors,
            ["Reference image not provided, unable to generate walk animation."],
        )

    @patch("pixellab_animator.PLClient")
    @patch("pixellab_animator.pil_image_open")
    @patch("pixellab_animator.PixellabAnimator._PixellabAnimator__upscale_animation")
    def test_generate_pixellab_animation_success(
        self, mock_upscale, mock_pil_open, mock_pl_client
    ):
        fake_image = MagicMock()
        fake_image.save.side_effect = lambda path: Path(path).write_bytes(b"fake")

        fake_response = MagicMock()
        fake_response.images = [
            MagicMock(pil_image=MagicMock(return_value=fake_image)) for _ in range(2)
        ]

        fake_client = MagicMock()
        mock_pl_client.return_value = fake_client

        with tempfile.TemporaryDirectory() as temp_dir:

            def fake_new_folder(path_str):
                folder = Path(temp_dir) / Path(path_str)
                folder.mkdir(parents=True, exist_ok=True)
                return str(folder)

            def fake_new_image_file_path(path_str):
                target_path = Path(temp_dir) / Path(path_str)
                target_path.parent.mkdir(parents=True, exist_ok=True)
                return str(target_path.with_suffix(".png"))

            mock_pil_open.return_value = MagicMock()
            animator = pixellab_animator.PixellabAnimator()

            with patch(
                "pixellab_animator.new_folder", side_effect=fake_new_folder
            ), patch(
                "pixellab_animator.new_image_file_path",
                side_effect=fake_new_image_file_path,
            ):
                char_data = CharacterData(
                    title="hero", description="A hero", ref_image_path="ref.png"
                )
                pixellab_animator.animate_with_text.return_value = fake_response
                result = animator.generate_pixellab_animation(
                    char_data.description,
                    "walk",
                    "animations",
                    char_data.ref_image_path,
                )

            self.assertEqual(result.errors, [])
            self.assertIn("walk", result.action_folders)
            self.assertTrue(Path(result.action_folders["walk"]).exists())

    @patch("pixellab_animator.PLClient")
    def test_generate_animations_composes_actions(self, mock_pl_client):
        fake_client = MagicMock()
        mock_pl_client.return_value = fake_client
        animator = pixellab_animator.PixellabAnimator()

        with patch.object(
            animator,
            "generate_pixellab_animation",
            return_value=PixellabAnimationResult(
                action_folders={"walk": "out"}, errors=[]
            ),
        ):
            request = AnimationRequest(
                char_data=CharacterData(
                    title="hero", description="A hero", ref_image_path="ref.png"
                ),
                actions=["walk"],
                base_folder="",
            )
            result = animator.generate_animations(request, "custom_folder")

        self.assertEqual(result.action_folders, {"walk": "out"})
        self.assertEqual(result.errors, [])


class TestPixellabGenerationScript(unittest.TestCase):
    @patch("pixellab_generation_script.OpenAIPixelArtGenerator")
    @patch("pixellab_generation_script.OpenAIActionDescriptionGenerator")
    @patch("pixellab_generation_script.PixellabAnimator")
    def test_generate_animations_with_mocked_api(
        self,
        mock_pixellab_animator_class,
        mock_action_description_class,
        mock_openai_class,
    ):
        openai_instance = MagicMock()
        openai_instance.generate_pixel_art_character.return_value = PixelArtResult(
            gen_image_path="ref.png", errors=[]
        )
        mock_openai_class.return_value = openai_instance

        action_description_instance = MagicMock()
        action_description_instance.generate_action_descriptions.return_value = (
            pixellab_generation_script.ActionDescriptionResult(
                action_descriptions={"walk": "walk with a steady side-view stride"},
                errors=[],
            )
        )
        mock_action_description_class.return_value = action_description_instance

        pixellab_instance = MagicMock()
        pixellab_instance.generate_animations.return_value = PixellabAnimationResult(
            action_folders={"walk": "out"}, errors=[]
        )
        mock_pixellab_animator_class.return_value = pixellab_instance

        with tempfile.TemporaryDirectory() as temp_dir:
            request_path = Path(temp_dir) / "request.json"
            request_data = {
                "char_data": {
                    "title": "hero",
                    "description": "A hero",
                    "ref_image_path": None,
                },
                "actions": ["walk"],
                "base_folder": "",
            }
            request_path.write_text(json.dumps(request_data))

            with patch.object(sys, "argv", ["script", str(request_path)]), patch(
                "pixellab_generation_script.new_folder",
                return_value=str(Path(temp_dir) / "ai_animations"),
            ):
                result = pixellab_generation_script.generate_animations()

        self.assertEqual(result.errors, [])
        self.assertEqual(result.action_folders, {"walk": "out"})


if __name__ == "__main__":
    unittest.main()
