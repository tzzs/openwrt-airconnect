import * as React from 'react';

import { fieldValue } from '../lib/fields.js';
import { Input } from './ui/input.jsx';
import { Label } from './ui/label.jsx';
import { Switch } from './ui/switch.jsx';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from './ui/select.jsx';

// Radix refuses an empty string as a SelectItem value, but "inherit the global
// setting" *is* the empty value in uci. Translate at the control boundary so the
// rest of the app only ever sees ''.
export const INHERIT = '__inherit__';

function toControl(value) {
  return value == null || value === '' ? INHERIT : String(value);
}

function fromControl(value) {
  return value === INHERIT ? '' : value;
}

/**
 * One control, rendered from a descriptor in lib/fields.js.
 *
 * The descriptor decides everything that can be wrong in a way a reviewer would
 * miss: which control, which options, whether empty means "inherit", and which
 * rule validates it. This component only paints it.
 */
export function Field({ field, value, onChange, rules, idPrefix, inheritLabel }) {
  const id = idPrefix + '-' + field.name;
  const effectiveValue = fieldValue(field, value);
  const rule = field.rule && rules ? rules[field.rule] : null;
  // An inheriting field accepts an empty value by definition; the rule only
  // applies once the user overrides it.
  const message =
    rule && !(field.inherit && (effectiveValue == null || effectiveValue === ''))
      ? rule(effectiveValue)
      : true;
  const invalid = typeof message === 'string';

  const choices = (field.options || []).map((option) =>
    option.value === '' ? { value: INHERIT, label: inheritLabel || option.label } : option,
  );

  const description = field.description ? (
    <p className="text-xs text-muted-foreground">{field.description}</p>
  ) : null;

  if (field.kind === 'flag' && !field.inherit) {
    return (
      <div className="ac-field-stack">
        <Label htmlFor={id}>{field.label}</Label>
        <div className="ac-field-control">
          <Switch
            id={id}
            checked={(effectiveValue ?? field.values[0]) === '1'}
            onCheckedChange={(checked) => onChange(checked ? '1' : '0')}
          />
        </div>
        {description}
      </div>
    );
  }

  if (field.kind === 'flag' || field.kind === 'select') {
    return (
      <div className="ac-field-stack">
        <Label htmlFor={id}>{field.label}</Label>
        <Select
          value={toControl(effectiveValue)}
          onValueChange={(next) => onChange(fromControl(next))}
        >
          <SelectTrigger id={id} aria-invalid={invalid ? 'true' : undefined}>
            <SelectValue />
          </SelectTrigger>
          <SelectContent>
            {choices.map((option) => (
              <SelectItem key={option.value} value={option.value}>
                {option.label}
              </SelectItem>
            ))}
          </SelectContent>
        </Select>
        {description}
        {invalid ? <p className="text-xs text-destructive">{message}</p> : null}
      </div>
    );
  }

  return (
    <div className="ac-field-stack">
      <Label htmlFor={id}>{field.label}</Label>
      <Input
        id={id}
        value={effectiveValue ?? ''}
        placeholder={field.placeholder || ''}
        aria-invalid={invalid ? 'true' : undefined}
        onChange={(event) => onChange(event.target.value)}
      />
      {description}
      {invalid ? <p className="text-xs text-destructive">{message}</p> : null}
    </div>
  );
}
