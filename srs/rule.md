### Repetitive Response & Loop Prevention
*   **No Periodic Repetition**: Do not output the same status, instructions, warnings, or message sequences across multiple turns.
*   **Self-Termination Guard**: If you observe that your previous 2 turns generated identical or highly similar messages, instructions, or planning statuses, immediately halt execution and output a single message asking the user for manual guidance.
*   **Duplicate Tool Calls**: Do not execute the same tool with identical arguments more than twice in the same conversation thread.
