extends Node
func _ready() -> void:
	await get_tree().create_timer(0.3).timeout
	print(await Watch.selftest("test"))
	get_tree().quit()
