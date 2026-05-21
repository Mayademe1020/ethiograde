---
version: "beta"
name: EthioGrade Product Design System
description: App-wide product design contract for an offline-first teacher workspace.
colors:
  primary: "#1B7A43"
  primary-hover: "#166636"
  primary-soft: "#EAF4EC"
  secondary: "#1A365D"
  accent: "#FCC312"
  danger: "#DA121A"
  danger-soft: "#FDECEC"
  info: "#2B6CB0"
  success: "#2F855A"
  warning: "#B7791F"
  text-primary: "#1A202C"
  text-secondary: "#4A5568"
  text-muted: "#5F6B7A"
  border-soft: "#D7E4DA"
  border-strong: "#AFC8B8"
  surface-page: "#F3F6F2"
  surface-card: "#FFFFFF"
  surface-muted: "#EEF4EF"
  surface-warning: "#FFF8E1"
typography:
  page-title:
    fontSize: 1.5rem
    fontWeight: 800
    lineHeight: 1.2
  section-label:
    fontSize: 0.75rem
    fontWeight: 800
    letterSpacing: 0.04em
  card-title:
    fontSize: 1rem
    fontWeight: 800
    lineHeight: 1.25
  body:
    fontSize: 0.95rem
    fontWeight: 400
    lineHeight: 1.45
  caption:
    fontSize: 0.78rem
    fontWeight: 600
    lineHeight: 1.35
rounded:
  chip: 10px
  control: 14px
  card: 18px
  hero: 26px
spacing:
  xs: 6px
  sm: 10px
  md: 16px
  lg: 20px
  xl: 28px
---

## Product Promise

EthioGrade is a calm, offline-first teacher workspace for Ethiopian classrooms.
It should feel fast, readable, trustworthy, and practical on low-end Android
phones, small screens, and bright classrooms. The app is not a generic
analytics dashboard. It helps a teacher answer one question quickly: what do I
do next?

## Principles

1. A teacher understands every screen in two seconds.
2. Each screen has one dominant action.
3. Secondary actions are quieter than the main action.
4. Text stays readable on small Android phones.
5. Contrast survives bright classrooms.
6. Forms minimize typing and required fields.
7. Offline-first trust is visible where it matters.
8. The tone is calm, professional, and Ethiopian-context aware.
9. Avoid Western-style complex dashboards.
10. Do not make all cards visually equal.

## Global Visual System

Use Ethiopian green as the action anchor, not as decoration everywhere. Yellow
is reserved for gentle attention and educational context. Red is only for
danger or destructive states. Most structure should come from spacing, borders,
and type hierarchy rather than heavy shadows.

Text colors must be strong: body text uses near-black, secondary text uses a
mid-gray with enough contrast, and placeholders should never be pale. Borders
must be visible on inexpensive screens. Prefer soft surfaces and clear labels
over decorative gradients.

## Typography

Hierarchy:

- Page title: screen identity, 22-24sp, bold.
- Section label: small uppercase or compact label, strong contrast.
- Card title: action or object name, 16-18sp, bold.
- Body text: practical explanation, 14-16sp.
- Metadata/caption: 12-13sp, still readable.

Avoid oversized hero text inside compact mobile panels. Do not scale text with
viewport width. Keep letter spacing at zero except short section labels.

## Components

### AppSection

Groups a related set of controls or content. It uses a clear section label, a
small optional subtitle, and one unframed content area. It should not look like
a nested card inside another card.

### AppCard

Default content surface. White background, visible border, 16-18px radius, no
heavy shadow. Use for student rows, settings groups, report summaries, and
empty states.

### PrimaryActionCard

The dominant card on a screen. It must contain one main action button with text.
It may show context and progress, but should not contain a grid of unrelated
actions.

### SettingsGroup and SettingsRow

SettingsGroup holds related rows with a title. SettingsRow uses an icon, title,
subtitle/value, and optional switch or chevron. Rows must be scan-friendly and
not feel like raw system preferences.

### StatCard

Quiet metric card. It supports the screen but never competes with the hero.
Use restrained borders and muted labels.

### FilterChip

Readable in both selected and unselected states. Selected chips use filled
green or high-contrast soft green with a check mark. Unselected chips use white
or muted surfaces with visible borders and dark text. Never rely on color alone.

### EmptyState

Explains what is missing and offers the next action. Keep copy short:
"No students yet. Add one student or import a roster."

### ConfirmDialog

Used for destructive or high-impact actions. It must name the consequence,
provide a calm cancel action, and use a red danger button for destructive
confirmation.

## Buttons

- Primary: filled green, white text, icon plus text when helpful.
- Secondary: outline or soft surface, green or dark text.
- Danger: filled or outlined red, never visually neutral.
- Disabled: clearly inactive but readable.
- Never show a primary button without text.

## Forms

Forms should feel like fast classroom tools. Ask only for what the teacher has
in hand. Use smart defaults, numeric keyboards for roll numbers and phone
numbers, and short validation messages. Optional fields are visibly optional.

## Screen Contracts

### Home

Purpose: tell the teacher what to do next.

The top area is a strong hero with dynamic greeting:
"Good Morning / Afternoon / Evening, {TeacherName}". It shows school and class
context as "{SchoolName} • {CurrentClass or ActiveSubject}". Ethiopian date is
visible but secondary.

The hero contains one dominant action: Continue Grading or Start Grading. If
unfinished work exists, show assessment name, class, reviewed count, and pending
count. Stats are quiet and supportive: Students, Assessments, Pending Review,
Completed Today. Recent Activity appears below and is lower priority.

### Settings

Purpose: give teacher control over profile, school, preferences, data, backup,
language, and app behavior.

Header: "Settings" and "Manage your profile, preferences, and data". Top
profile card shows teacher name, school name, active class/subject, and Edit
Profile. Groups are Account, Grading Preferences, Appearance, Data & Security,
Support, About, and Danger Zone. Clear All Data is red and requires a
confirmation dialog.

### Students List

Purpose: help teachers quickly find, add, import, and manage students.

Search supports name and student ID. Add Student and Import Roster are obvious.
Class/grade chips are readable with clear selected state. Show total student
count. Empty state: "No students yet. Add one student or import a roster."

### Add Student

Purpose: add one student quickly with minimum required information.

Required fields: Full Name and Student ID / Roll No. Remove additional name
sections. Gender is optional and supports Skip/Unknown. Class auto-selects when
there is one class or when opened from a class. Use a sticky bottom Save Student
button where appropriate. Parent phone is optional.

### Assess / Grading

Purpose: start, continue, and review grading work.

Use one dominant action: Scan Papers, Continue Review, or Create Assessment.
Unfinished work must be obvious. Review states are Not scanned, Needs review,
Confirmed, and Completed. Status colors are only for status.

### Results / Reports

Purpose: help teachers trust, review, and export scores.

Show assessment name, class, date, and completion status at the top. Make
export/share visible. Missing or ungraded students are clear. Recalculation or
answer-key changes must be visible. Tables must stay readable on small screens.

## States

Loading states use skeleton or compact progress with clear copy. Error states
explain what happened and the next recovery action. Offline states should say
"No internet required" or "Data stays on your phone" where relevant, without
overloading Home with technical privacy copy.

## Performance

The interface must stay lightweight. Avoid heavy animation, large shadows, and
expensive visual effects. Use simple surfaces, stable layout dimensions, and
fast local interactions.
