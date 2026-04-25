# Private Boundary Notes

Current version: `v1.0.0-14-g59bd5dc`

Keep the public CrispyBrain repo focused on the reusable product core.

## Keep Out Of This Repo

- CMS implementation details unless they are intentionally released later
- client-specific prompts, workflows, or integrations
- private operational notes tied to one team or one machine
- customer data, private examples, or derived memory content
- unpublished adjacent systems that are not required for CrispyBrain itself
- one-off internal experiments that do not improve the public product path

## Why This Matters

The public repo should stay small enough to understand, explain, and adopt. Private or client-specific material tends to make the public architecture look more complicated than it really is.

## Practical Test

Before adding something to the repo, ask:

1. Does this help an outside operator run or understand CrispyBrain?
2. Is it reusable beyond one private environment?
3. Would we be comfortable explaining it on the public README?

If the answer is no, it probably belongs elsewhere.
