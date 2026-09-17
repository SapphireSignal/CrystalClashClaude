class_name MenuLayout
extends RefCounted
## The menu client's GUI canvas. `TGameStateManager.SetClientWindow` sets `GUI.VirtualSize := CLIENT_DEFAULT_DIMENSIONS`
## in every branch, so the whole menu is authored on a fixed **1280x720** canvas and scaled to the client window:
## at 1920x1080 every element is 1.5x larger, the layout identical. (The game window does the opposite —
## `SetGameWindow` sets `GUI.VirtualSize := ZERO`, so the in-match HUD is absolute pixels with the `.small` switch.)
##
## Verified against `reference/rolmedia/lobby`: the 1280x720 leaderboards shot upscaled 1.5x matches the 1920x1080
## one about four times better than an absolute-pixel overlay does (0.25 vs 0.85 normalized mean error).
##
## `apply()` puts the scale on the menu's CanvasLayer; every menu control lays out against `layout_size()`, which
## divides the real viewport by that scale (and so returns the plain viewport size in the unscaled game window).

const SIZE := Vector2(1280, 720)   # CLIENT_DEFAULT_DIMENSIONS


static func scale_for(window: Vector2) -> float:
	if window.x <= 0.0 or window.y <= 0.0:
		return 1.0
	return minf(window.x / SIZE.x, window.y / SIZE.y)


## Scales the layer to the window and centres the canvas (the original sizes its window to 16:9, so the
## letterbox offset is normally zero).
static func apply(layer: CanvasLayer) -> void:
	var window := Vector2(DisplayServer.window_get_size())
	var s := scale_for(window)
	layer.transform = Transform2D(0.0, Vector2(s, s), 0.0, ((window - SIZE * s) / 2.0).floor())


## The size a control should lay out against: the canvas size of its CanvasLayer, or the viewport when unscaled.
static func layout_size(node: CanvasItem) -> Vector2:
	var view := node.get_viewport_rect().size
	var n: Node = node
	while n != null:
		if n is CanvasLayer:
			var s: Vector2 = (n as CanvasLayer).transform.get_scale()
			return view / s if s.x > 0.0 and s.y > 0.0 else view
		n = n.get_parent()
	return view
