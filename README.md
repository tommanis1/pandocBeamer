# Scripts for HTML Slides from Markdown Using Pandoc

## Usage

Run the Python script:
```bash
pandocBeamer
```

## Examples

*To be added*, see examples/ for a single example

## TODO

Numerous items:

- [ ] `\tikz` command is only recognised in rawblock

  **Current requirement:**
  ````md
  ```{=tex}
  \tikz{\cat{topics.tikz}, width=50% .centered}
  ```
  ````
  
  **Desired syntax:**
  ```
  \tikz{\cat{topics.tikz}, width=50% .centered}
  ```
