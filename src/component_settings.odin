package parior_messenger

import "gui:skald"

theme_toggled :: proc(value: bool) -> Msg {
	return Theme_Toggled(value)
}

settings_view :: proc(state: State, ctx: ^skald.Ctx(Msg)) -> skald.View {
	return skald.toggle(ctx, state.dark_theme, state.dark_theme ? "Dark" : "Light", theme_toggled,
		id = skald.hash_id("theme-toggle"))
}
