---
name: text-reverse
description: Reverses a string so that its characters appear in the opposite order. Use this skill whenever the user asks to reverse text, flip a string backwards, invert the character order, or produce the mirror form of a word or sentence.
---

# Text Reverse

Reverse the input string character by character.

## Rules
- Keep every character, including spaces and punctuation.
- Reverse the full character sequence, not just the word order.

## Output
Report the result with exactly one XML tool call:

<function name="reverse_report">
<param name="reversed">REVERSED_STRING</param>
</function>