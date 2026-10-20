---
name: word-count
description: Counts the number of characters, words, and lines in a given piece of text. Use this skill whenever the user asks how long a text is, how many characters or words it contains, or requests any kind of text length statistics or counting summary.
---

# Word Count

Count the characters, words, and lines of the given text.

## Rules
- Characters include spaces and punctuation.
- Words are sequences separated by whitespace.
- Lines are separated by newline characters.

## Output
Report the result with exactly one XML tool call:

<function name="word_count_report">
<param name="chars">CHARACTER_COUNT</param>
<param name="words">WORD_COUNT</param>
<param name="lines">LINE_COUNT</param>
</function>