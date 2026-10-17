---
version: "2.0"
name: EthioGrade Design System
description: Professional, teacher-first design for offline grading on low-end Android phones.
---

## Product Promise

EthioGrade is a calm, offline-first teacher workspace for Ethiopian classrooms.
It helps teachers turn paper exams into trusted grades quickly, with review
and export, on low-end phones under classroom pressure.

## Design Principles

1. **One dominant action per screen** — teachers know what to do in 2 seconds
2. **Calm and professional** — not flashy, not overwhelming
3. **Readable on small Android phones** — 320px viewport, bright classrooms
4. **High contrast** — survives bright sunlight and dim staff rooms
5. **Minimal typing** — scan and confirm over manual entry
6. **Trust visible** — data stays on phone, review before save
7. **Recoverable** — drafts auto-save, nothing lost on crash

## Color System

### Brand
- Primary: `#0B6E4F` (deep teal-green — action anchor)
- Primary Light: `#1A8A65`
- Primary Container: `#DFF5EC`
- Secondary: `#F4A623` (warm amber — gentle attention)
- Tertiary: `#DA2A2A` (alert red — danger only)

### Semantic
- Success: `#18A558`
- Warning: `#F4A623`
- Error: `#DA2A2A`
- Info: `#1A6FD4`

### Surfaces
- Scaffold Light: `#F4F7F5`
- Surface: `#FFFFFF`
- Surface Variant: `#F0F4F2`
- Outline: `#DDE4E0`

## Typography

Font: Plus Jakarta Sans

- Page title: 24sp, w700
- Section label: 11sp, w500, uppercase
- Card title: 17sp, w700
- Body: 14sp, w400
- Caption: 12sp, w400

## Spacing & Radius

### Spacing (AppSpacing)
- xs: 4, sm: 8, md: 16, lg: 24, xl: 32, xxl: 48

### Radius (AppRadius)
- sm: 8, md: 12, lg: 16, xl: 20, xxl: 28, full: 999

## Component Patterns

### Cards
- Border radius: 20px
- Border: 1px outline
- No shadow (clean flat design)
- Padding: 16px

### Buttons
- Primary: teal-green fill, white text, 52px height
- Secondary: teal-green outline, 52px height
- All buttons: 16px border radius

### Navigation
- Bottom navigation bar with 4 tabs
- Home, Assess, Students, Settings
- Active tab: teal-green indicator + bold label

## Teacher-Friendly Patterns

### Dashboard Home
- Greeting with teacher name
- Resume grading banner (if draft exists)
- 3 quick stats (Students, Active, Completed)
- Primary action card (dynamic CTA based on state)
- My Classes horizontal scroll
- Recent Assessments list
- Quick actions

### Assessment Cards
- Show next action: "Add answer key", "Scan papers", "Review results"
- Status chips: needs setup, ready to scan, completed
- One-tap primary action

### Scan Screen
- Camera preview with guide overlay
- Flash toggle
- Auto/Manual scan mode
- Capture count
- Done button

### Review Screen
- Side-by-side verification
- Confidence indicators
- Step-through recovery
- Export/save final grades

## Offline Trust Signals

- "Data stays on your phone" visible at key moments
- Backup prompts before destructive actions
- Draft resume banner on home screen
- Clear scan failure recovery messages
