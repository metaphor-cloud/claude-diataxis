"""Symbol inventory via the ast module. Used by the python adapter only when
a python interpreter is present and griffe is not. Emits NDJSON records:
{name, kind, signature, path, line, visibility, doc_comment, strategy}.

Respects __all__ when defined at module level: names outside it are marked
visibility "internal".
"""
import ast
import json
import sys


def signature_of(node):
    if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)):
        try:
            args = ast.unparse(node.args)
        except Exception:
            args = "..."
        ret = ""
        if node.returns is not None:
            try:
                ret = " -> " + ast.unparse(node.returns)
            except Exception:
                ret = ""
        prefix = "async def" if isinstance(node, ast.AsyncFunctionDef) else "def"
        return "%s %s(%s)%s" % (prefix, node.name, args, ret)
    if isinstance(node, ast.ClassDef):
        bases = []
        for b in node.bases:
            try:
                bases.append(ast.unparse(b))
            except Exception:
                pass
        return "class %s(%s)" % (node.name, ", ".join(bases)) if bases else "class %s" % node.name
    return node.name if hasattr(node, "name") else ""


def module_all(tree):
    for node in tree.body:
        if isinstance(node, ast.Assign):
            for target in node.targets:
                if isinstance(target, ast.Name) and target.id == "__all__":
                    try:
                        return [str(v) for v in ast.literal_eval(node.value)]
                    except Exception:
                        return None
    return None


def emit(path, node, kind, exported):
    name = node.name if hasattr(node, "name") else None
    if not name:
        return
    visibility = "public"
    if name.startswith("_"):
        visibility = "internal"
    if exported is not None and name not in exported:
        visibility = "internal"
    doc = ast.get_docstring(node) or ""
    print(json.dumps({
        "name": name,
        "kind": kind,
        "signature": signature_of(node),
        "path": path,
        "line": node.lineno,
        "visibility": visibility,
        "doc_comment": doc,
        "strategy": "python-ast",
    }))


def main():
    for path in sys.argv[1:]:
        try:
            with open(path, "r", encoding="utf-8", errors="replace") as fh:
                tree = ast.parse(fh.read(), filename=path)
        except (SyntaxError, OSError):
            continue
        exported = module_all(tree)
        for node in tree.body:
            if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)):
                emit(path, node, "function", exported)
            elif isinstance(node, ast.ClassDef):
                emit(path, node, "class", exported)
                for sub in node.body:
                    if isinstance(sub, (ast.FunctionDef, ast.AsyncFunctionDef)):
                        if not sub.name.startswith("_"):
                            emit(path, sub, "method", None)


if __name__ == "__main__":
    main()
