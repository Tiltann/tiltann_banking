// Every errorKey a server callback can return (see server/*/*.lua's
// `---@return string? errorReason` doc comments) has a matching
// `error.<key>` entry in i18n/strings.ts. This just resolves one through the
// active translation function, humanizing anything unmapped rather than ever
// showing a raw snake_case key.
export function describeError(errorKey: string | undefined, t: (key: string) => string): string {
	if (!errorKey) {
		return t('error.default');
	}

	const translated = t(`error.${errorKey}`);

	if (translated !== `error.${errorKey}`) {
		return translated;
	}

	return errorKey
		.split('_')
		.map((word) => word.charAt(0).toUpperCase() + word.slice(1))
		.join(' ') + '.';
}
