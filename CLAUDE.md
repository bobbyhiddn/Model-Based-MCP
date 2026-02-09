# Model-Based-MCP

MCP server for creating SysML/MBSE diagrams and hierarchical canvas diagrams as PNGs.

Forked from [Canvas-MCP](https://github.com/bobbyhiddn/Canvas-MCP) with added support for model-based systems engineering diagram types.

## Architecture

- **`src/model_based_mcp/models.py`** — Ontology: Canvas > Network > Factory > Machine > Node, plus NodeStyle, ContainerStyle, and SysML node types
- **`src/model_based_mcp/parser.py`** — YAML recipe parser (supports hierarchical format + simplified format)
- **`src/model_based_mcp/renderer.py`** — Pillow-based PNG renderer with Catppuccin dark theme
- **`src/model_based_mcp/organize.py`** — Hierarchical layout algorithm (topological sort + parent-center alignment)
- **`src/model_based_mcp/server.py`** — MCP server with tools: `render_model`, `create_model`, `list_templates`, `get_template`
- **`templates/`** — Starter recipe templates

## Ontology

Four-level hierarchy: Canvas > Network > Factory > Machine > Node.

Every level has `id` (required, unique) + `label` (optional display name) + `description` (optional docs).
All levels expose `get_label()` which returns `label` if set, otherwise `id`.

- **Network** — system boundary (broadest scope)
- **Factory** — functional domain (groups related pipelines)
- **Machine** — pipeline (connected chain of operations)
- **Node** — atomic operation (the leaf unit)

## Styling

- **NodeStyle** — controls node appearance (border_color, fill_color, text_color, label_color, corner_radius)
- **ContainerStyle** — controls machine/factory containers (border_color, fill_color, label_color, alpha, corner_radius, border_width)

## Node Types & Colors

### Canvas Types (inherited from Canvas-MCP)

| Type | Color | Use |
|------|-------|-----|
| `input` | Blue (#2196F3) | User input / data entering the system |
| `output` | Amber (#FFC107) | Final results leaving the system |
| `process` | Cyan (#00BCD4) | Transformation or computation step |
| `decision` | Red (#F44336) | Branching / conditional gate |
| `ai` | Purple (#9C27B0) | AI/LLM processing step |
| `source` | Orange (#FF9800) | External data source |
| `static` | Green (#4CAF50) | Immutable seed content |
| `default` | Gray (#999) | Generic / unspecified |

### SysML/MBSE Types

| Type | Color | Use |
|------|-------|-----|
| `block` | Light Blue (#42A5F5) | SysML block — structural element (BDD/IBD) |
| `port` | Light Purple (#AB47BC) | SysML port — interface point on a block |
| `requirement` | Light Green (#66BB6A) | SysML requirement — system requirement |
| `constraint` | Light Red (#EF5350) | SysML constraint — parametric constraint |
| `activity` | Teal (#26C6DA) | SysML activity — action or behavior |
| `signal` | Yellow (#FFCA28) | SysML signal — event or message |

## YAML Formats

### Simplified (auto-layout)
```yaml
title: My Diagram
nodes:
  - id: start
    type: input
    content: "Begin"
    outputs: [next]
  - id: next
    type: process
    content: "Do work"
    inputs: [start]
```

### Hierarchical (explicit coordinates)
```yaml
canvas:
  version: "2.0"
  title: My Canvas
  networks:
    - id: network-1
      factories:
        - id: factory-1
          machines:
            - id: machine-1
              nodes:
                - id: node-1
                  type: block
                  x: 100
                  y: 100
                  content: "Vehicle System"
```

## Running

```bash
uv run model-based-mcp   # Starts MCP stdio server
```

## Testing

```bash
uv run python test_render.py  # Renders test PNGs to output/
```
