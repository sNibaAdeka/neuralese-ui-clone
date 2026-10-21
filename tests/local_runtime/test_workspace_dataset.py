import json

import pytest

from neuralese_local.dataset_store import load_godot_json_dataset


def test_workspace_images_keep_validation_and_image_dimensions(tmp_path):
    path = tmp_path / "images.json"
    path.write_text(json.dumps({
        "x": [[0, 1, 0, 1]], "y": [[1, 0]],
        "val_x": [[1, 0, 1, 0]], "val_y": [[0, 1]],
        "meta": {"preview": {"inputs": {"datatype": "2d", "x": 2, "y": 2}}},
    }))
    dataset = load_godot_json_dataset(path)
    assert dataset.x.shape == (1, 1, 2, 2)
    validation, targets = dataset.validation_arrays()
    assert validation.shape == (1, 1, 2, 2)
    assert validation[0, 0, 0, 0] == 1
    assert targets.tolist() == [[0, 1]]


@pytest.mark.parametrize("extra", [
    {"val_x": [[1, 2]]},
    {"val_x": [[1, 2]], "val_y": []},
    {"meta": {"preview": {"inputs": {"datatype": "2d", "x": 4, "y": 4}}}},
])
def test_workspace_rejects_inconsistent_training_payload(tmp_path, extra):
    path = tmp_path / "invalid.json"
    path.write_text(json.dumps({"x": [[1, 2]], "y": [0], **extra}))
    with pytest.raises(ValueError):
        load_godot_json_dataset(path)
