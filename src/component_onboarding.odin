package parior_messenger

import "core:strings"

import "gui:skald"

nickname_changed :: proc(value: string) -> Msg {
	return Nickname_Changed(value)
}

bind_changed :: proc(value: string) -> Msg {
	clean, _ := strings.replace_all(value, "\n", "", context.temp_allocator)
	return Bind_Changed(clean)
}

port_changed :: proc(value: string) -> Msg {
	return Port_Changed(value)
}

onboarding_view :: proc(state: State, ctx: ^skald.Ctx(Msg), size: [2]f32) -> skald.View {
	theme := ctx.theme
	outer_padding := theme.spacing.lg
	form_width := min(f32(500), max(f32(220), size.x - 2 * outer_padding))
	field_width := max(f32(0), form_width - 2 * theme.spacing.xl)
	form := skald.col(
		skald.text("Welcome to Parior", theme.color.fg, theme.font.size_xl),
		skald.text("Choose the Barev identity this device will use.", theme.color.fg_muted, theme.font.size_md, max_width = 440),
		skald.spacer(theme.spacing.sm),
		skald.text("Nickname", theme.color.fg, theme.font.size_sm),
		skald.text_input(ctx, state.nickname_draft, nickname_changed,
			id = skald.hash_id("onboarding-nickname"), placeholder = "alice", width = field_width),
		skald.text("Yggdrasil IPv6 address", theme.color.fg, theme.font.size_sm),
		skald.text_input(ctx, state.bind_draft, bind_changed,
			id = skald.hash_id("onboarding-address"), placeholder = "201:db8::1",
			width = field_width, height = 64, multiline = true, wrap = true),
		skald.text("Listening port", theme.color.fg, theme.font.size_sm),
		skald.text_input(ctx, state.port_draft, port_changed,
			id = skald.hash_id("onboarding-port"), placeholder = "5299", width = field_width),
		skald.toggle(ctx, state.dark_theme, state.dark_theme ? "Dark theme" : "Light theme", theme_toggled,
			id = skald.hash_id("onboarding-theme")),
		skald.button(ctx, "Start messaging", Msg(Complete_Onboarding{}),
			id = skald.hash_id("complete-onboarding"), width = field_width),
		width = form_width,
		spacing = theme.spacing.sm,
		padding = theme.spacing.xl,
		bg = theme.color.surface,
		radius = theme.radius.lg,
		cross_align = .Stretch,
	)
	content_height := max(f32(580), size.y)
	content := skald.row(
		skald.flex(1, skald.spacer(0)), form, skald.flex(1, skald.spacer(0)),
		width = size.x, height = content_height, padding = outer_padding,
		bg = theme.color.bg, cross_align = .Center)
	return skald.scroll(ctx, size, content, id = skald.hash_id("onboarding-scroll"))
}
