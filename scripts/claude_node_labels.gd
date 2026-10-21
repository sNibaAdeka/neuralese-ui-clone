extends RefCounted
## Presentation names only; registry IDs, serialization and execution stay intact.
const TITLES := {
	"input": "Ввод 2D", "input_1d": "Ввод 1D", "dataset": "Датасет",
	"layer": "Плотный слой", "neuron": "Активация", "NeuronLayer": "Плотный слой",
	"conv2d": "Свёртка 2D", "maxpool": "Макспул", "dropout": "Дропаут",
	"gru_cell": "Память GRU", "flatten": "Плоский 1D", "reshape2d": "Форма 2D",
	"concat": "Склейка", "softmax": "Софтмакс", "classifier": "Классификатор",
	"label_group": "Классификатор", "train_begin": "Начать обучение",
	"run_model": "Запуск модели", "train_input": "Шаг обучения",
	"train_rl": "Обучение с наградой", "model_name": "Имя модели",
	"augment_tf": "Преобразование данных", "lua_env": "Сценарий Lua",
}

static func title(type_id: String, fallback: String) -> String:
	return str(TITLES.get(type_id, fallback))
