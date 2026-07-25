extends Control

## Chase end overlay is superseded by WinScreen for the finale.
## Kept hidden; chase flows into GameProgress.report_chase_finished.


func _ready() -> void:
	visible = false
