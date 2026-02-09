# Model-Based-MCP Examples

Example YAML recipes demonstrating the Model-Based-MCP hierarchical diagram format.
These examples were inherited from Canvas-MCP and demonstrate the core rendering capabilities.

## Hierarchical Format (full ontology)

These examples use the full `canvas > networks > factories > machines > nodes` hierarchy with explicit coordinates:

| File | Description |
|------|-------------|
| `rhode-architecture.yaml` | Real-world system architecture for the Rhode ordinal agent system. Multi-network layout with custom container styling (Catppuccin colors), 4 networks, 7 factories, and 20+ nodes. |
| `concurrency-test.yaml` | Project risk analysis pipeline. A factory of sequential machines feeds into a parallel fan-out (go/no-go + executive summary) that merges into a final report. |
| `risk-chain.yaml` | Shorter risk analysis chain. Three sequential machines (identify risks, assess probability, generate mitigations) followed by parallel decision and summary tracks. |
| `etymology-factory.yaml` | Etymology study pipeline. A seed word fans out to three parallel analysis machines (history, prefix/suffix, language breakdown) that converge into a compiled study and expanded document. |
| `network-container-spacing-demo.yaml` | Multi-factory spacing demo. Three factories with fan-out/fan-in patterns, demonstrating container nesting and cross-factory connections. |
| `color-codes.yaml` | Context propagation test. Code words flow through factories and machines, testing how information merges and filters across container boundaries. |
| `interview-sim.yaml` | Interview simulation from a PDF resume source. Demonstrates `pdf_file_source` and `text_file_output` node types (extended I/O node types). |
| `turing-machine.yaml` | Document summarization from PDF and text file sources. Minimal example of file-based I/O nodes. |

## How to render

Use the `render_model` MCP tool or render directly:

```bash
uv run python -c "
from model_based_mcp.parser import parse_yaml
from model_based_mcp.renderer import CanvasRenderer

with open('examples/rhode-architecture.yaml') as f:
    canvas = parse_yaml(f.read())
renderer = CanvasRenderer(scale=2.0)
renderer.render(canvas, output_path='output/rhode-architecture.png', organize=True)
"
```

## Notes

- Some examples use extended node types (`pdf_file_source`, `text_file_source`, `text_file_output`) that will render as `default` type nodes.
- The `rhode-architecture.yaml` was authored for the [Rhode](https://github.com/bobbyhiddn/Rhode) project and demonstrates production-grade use of custom `ContainerStyle` with Catppuccin Mocha colors.
- All coordinates in these files are explicit. To test auto-layout, remove the `x`/`y` fields and use `organize: true`.
