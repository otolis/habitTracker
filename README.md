#Habit Tracker (Flutter, local-only)

A lightweight, offline habit tracker built with Flutter and Material 3. It supports two habit types (check and count), a progress ring for count goals, an 8-week heatmap, streaks, dark/light mode with persistence, and simple local JSON storage. No backend required.

#Features

Two habit types

check: done/not done per day

count: increment/decrement toward a daily goal (shows a progress ring)

Weekly heatmap (last 8 weeks)

Current streak and best streak

Create, edit, delete habits

Emoji and color picker per habit

Dark/light mode toggle (saved across launches)

Local, file-based storage (single JSON file)

#Data & Persistence

App data is saved as JSON in the app’s documents directory:

habits.json — list of habits and their daily completion/count history

settings.json — UI preferences (e.g., theme mode)

Habit serialization includes:

id, name, emoji, colorValue

type (check or count)

goalCount (for count habits)

createdAt

completedDays (for check)

dayCounts (for count)