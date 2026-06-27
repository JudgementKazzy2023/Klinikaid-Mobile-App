# Contributing to KlinikAid Mobile

As a private capstone repository, contribution is restricted to authorized team members.

## Workflow

1. **Setup**: Refer to [docs/03-setup.md](file:///docs/03-setup.md) for local environment setup.
2. **Branching**: Develop features in separate branches (`feature/name` or `bugfix/name`) off `main`. Submit a pull request when complete.
3. **Commit Messages**: Follow the conventional commit format: `type(scope): description` (e.g., `fix(ocr): resolve camera loop`).
4. **Code Quality**: Ensure the codebase is warning-free by running `flutter analyze` prior to committing.
5. **Testing**: Write widget/unit tests under `test/` for new functionality. Ensure the full test suite runs successfully via `flutter test`.
