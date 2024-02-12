# Parser Control Flow

Rough pseudocode for the following input:

```markdown
> - Hello, World!
> > New child!
```

Which should form the syntax tree:

```
- Document
  - Quote
    - List
      - ListItem
        - Paragraph
          - Text
    - Quote
      - Paragraph
        - Text
```

- `Document.handleLine()` **"> - Hello, World!"**
  - open child? -> false
  - `parseBlockFromLine()` **"> - Hello, World!"**
    - `Quote.handleLine()`
      - open child? -> false
      - `parseBlockFromLine()` **"- Hello, World!"**
        - `List.handleLine()`
          - open ListItem? -> false
          - `ListItem.handleLine()`
            - open child? -> false
            - `parseBlockFromLine()` **"Hello, World!"**
              - `Paragraph.handleLine()`
                - *todo* `parseInlines()`?
            - `ListItem.addChild(Paragraph)`
        - `List.addChild(ListItem)`
      - `Quote.addChild(List)`
  - `Document.addChild(Quote)`
- `Document.handleLine()` **"> > New Child!"**
  - open child? -> true
  - `openChild.handleLine()`? -> true
    - `Quote.handleLine()` **"> > New Child!"**
      - open child? -> true
        - `List.handleLine()` -> false **"> New Child!"**
          - List may not start with **">"**
        - child.close()
      - `parseBlockFromLine()` **"> New Child!"**
        - `Quote.handleLine()`
          - open child? -> false
          - `parseBlockFromLine()` **"New Child!"**
            - `Paragraph.handleLine()`
              - *todo* parseInlines()?
          - `Quote.addChild(Paragraph)`
      - `Quote.addChild(Quote)`
- `Document.closeChildren()` **"EOF"**
