import { Activity, Monitor, Moon, RefreshCw, RotateCcw, Sun } from 'lucide-react';

import { Button } from './ui/button.jsx';
import { LANGUAGES } from '../lib/i18n.js';
import { THEMES } from '../lib/theme.js';

/**
 * The chrome both AirConnect pages share: the product lockup, the status
 * readout, the language and theme switches, and the save actions.
 *
 * It lives here rather than in either page because the two pages are the same
 * application with a different body.
 *
 * The language and theme preferences are owned by the app, not by the chrome:
 * the body needs the translator that the language produces, and the body is a
 * sibling of the chrome, not a child. So the chrome receives the current
 * values and the change callbacks.
 *
 * The theme has to live on the `.ac-root` element, which the LuCI view creates
 * outside the React tree, so the host element is passed in and the classes are
 * toggled on it. `system` adds no class at all: the stylesheet's
 * `prefers-color-scheme` block decides, which is why the OS can change the
 * page's appearance without any JavaScript running.
 */
export function PageChrome({
	themeHost,
	theme,
	lang,
	onLanguageChange,
	onThemeChange,
	t,
	children,
	status,
	saveState,
	busy,
	onSave,
	onSaveApply,
	onReset,
	onRefresh,
	extraActions,
	title,
	subtitle
}) {
	const services = (status && status.services) || {};
	const running =
		(services.upnp && services.upnp.running) ||
		(services.cast && services.cast.running);

	return (
		<div className="ac-chrome">
			<div className="ac-chrome-bar">
				<div className="ac-brand-lockup">
					<div className="ac-brand-mark">
						<Activity />
					</div>
					<div>
						<strong>AirConnect</strong>
						<span>{t('Speaker bridge')}</span>
					</div>
				</div>

				<div className="ac-chrome-status">
					<span
						className={
							'ac-service-indicator ' + (running ? 'is-running' : 'is-stopped')
						}
						role="status"
						aria-live="polite"
					>
						<span className="ac-service-indicator-dot" />
						{running ? t('Service running') : t('Service stopped')}
					</span>
					{saveState ? (
						<span
							className={'ac-save-state ac-save-' + saveState.tone}
							role="status"
							aria-live="polite"
						>
							{saveState.text}
						</span>
					) : null}
				</div>

				{/*
				 * Every control is a shadcn Button with an explicit
				 * type="button": the app is mounted inside a LuCI view, and a
				 * button without a type defaults to submit. Icon-only buttons
				 * carry both a title and an aria-label, because an icon alone
				 * is not an accessible name.
				 */}
				<div className="ac-chrome-actions">
					{extraActions}
					<div className="ac-preferences" role="group" aria-label="Language">
						{LANGUAGES.map((entry) => (
							<Button
								key={entry.value}
								variant={entry.value === lang ? 'secondary' : 'ghost'}
								size="sm"
								type="button"
								className="ac-lang-button"
								aria-pressed={entry.value === lang}
								title={entry.label}
								aria-label={entry.label}
								onClick={() => onLanguageChange(entry.value)}
							>
								{entry.value === 'zh' ? '中' : 'EN'}
							</Button>
						))}
					</div>
					<div className="ac-preferences" role="group" aria-label="Theme">
						{THEMES.map((entry) => {
							const Icon =
								entry.value === 'light'
									? Sun
									: entry.value === 'dark'
										? Moon
										: Monitor;
							return (
								<Button
									key={entry.value}
									variant={entry.value === theme ? 'secondary' : 'ghost'}
									size="icon"
									type="button"
									className="ac-icon-button"
									aria-pressed={entry.value === theme}
									title={t(entry.label)}
									aria-label={t(entry.label)}
									onClick={() => onThemeChange(entry.value)}
								>
									<Icon />
								</Button>
							);
						})}
					</div>
					{onRefresh ? (
						<Button
							variant="ghost"
							size="icon"
							type="button"
							className="ac-icon-button"
							disabled={busy}
							onClick={onRefresh}
							title={t('Refresh status')}
							aria-label={t('Refresh status')}
						>
							<RefreshCw />
						</Button>
					) : null}
					{onReset ? (
						<Button
							variant="ghost"
							size="icon"
							type="button"
							className="ac-icon-button"
							disabled={busy}
							onClick={onReset}
							title={t('Reset')}
							aria-label={t('Reset')}
						>
							<RotateCcw />
						</Button>
					) : null}
					{onSave ? (
						<Button
							variant="outline"
							size="sm"
							type="button"
							disabled={busy}
							onClick={onSave}
						>
							{t('Save')}
						</Button>
					) : null}
					{onSaveApply ? (
						<Button
							size="sm"
							type="button"
							disabled={busy}
							onClick={onSaveApply}
						>
							{t('Save and apply')}
						</Button>
					) : null}
				</div>
			</div>
			{title ? (
				<div className="ac-chrome-title">
					<h1>{title}</h1>
					{subtitle ? <p>{subtitle}</p> : null}
				</div>
			) : null}
			{children}
		</div>
	);
}
