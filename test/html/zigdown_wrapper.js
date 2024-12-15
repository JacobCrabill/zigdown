const text_decoder = new TextDecoder();
const text_encoder = new TextEncoder();
let console_log_buffer = "";
let html_render_buffer = "";

const placeholder_markdown =
  ['# Live WASM Markdown Previewer',
  '',
  '```{toc}',
  '```',

  'Enter Markdown above; it will be rendered here in real-time in the browser',
  'using the WebAssembly version of [Zigdown](https://github.com/JacobCrabill/zigdown).',
  '',
  '## Demo',
  '',
  '### Table of Contents',
  '',
  'See the Table of Contents rendered above; this can be auto-generated with:',
  '',
  '````markdown',
  '```{toc}',
  '```',
  '````',

  'Code blocks are supported, but compiling TreeSitter for WASM is still a WIP,',
  'so no syntax highlighting is possible (yet).',
  '',
  '### Links',
  '',
  'Links like [this](jcrabill.dev) can be added like `[text](url)`',
  '',
  '### Images',
  '',
  'Images can be added like `![alt-text](src-uri)`:',
  '',
  '![sample](zig-zero.png)'].join('\n');

let wasm = {
    instance: undefined,

    init: function (obj) {
        this.instance = obj.instance;
    },

    // Get a string from WASM memory into JavaScript
    getString: function (ptr, len) {
        const memory = this.instance.exports.memory;
        return text_decoder.decode(new Uint8Array(memory.buffer, ptr, len));
    },

    // Encode a string from JavaScript into a utf-8 string in WASM memory
    encodeString: function (string) {
        const memory = this.instance.exports.memory;
        const allocUint8 = this.instance.exports.allocUint8;
        const buffer = text_encoder.encode(string);
        const pointer = allocUint8(buffer.length + 1); // ask Zig to allocate memory
        const slice = new Uint8Array(
            memory.buffer, // memory exported from Zig
            pointer,
            buffer.length + 1
        );
        // Copy encoded string into allocated buffer
        slice.set(buffer);
        slice[buffer.length] = 0; // null byte to null-terminate the string
        return pointer;
    },

    renderToHtml: function (md) {
        // Encode the Markdown text from JavaScript into WASM memory
        const md_ptr = this.encodeString(md);
        this.instance.exports.renderToHtml(md_ptr);
        // Zig will call jsHtmlBufferWrite() and jsConsoleLogFlush()
    },
};

let importObject = {
    env: {
        jsConsoleLogWrite: function (ptr, len) {
            console_log_buffer += wasm.getString(ptr, len);
        },
        jsConsoleLogFlush: function () {
            console.log(console_log_buffer);
            console_log_buffer = "";
        },
        jsHtmlBufferWrite: function (ptr, len) {
            html_render_buffer += wasm.getString(ptr, len);
        },
        jsHtmlBufferFlush: function () {
            let rbox = document.getElementById("renderbox");
            rbox.innerHTML = html_render_buffer;
            html_render_buffer = "";
        }
    }
};

function renderFromInput() {
  const text = document.getElementById("input_box").value
  if (text == "") {
    wasm.renderToHtml(placeholder_markdown);
  } else {
    wasm.renderToHtml(document.getElementById("input_box").value);
  }
}

async function bootstrap() {
    wasm.init(await WebAssembly.instantiateStreaming(fetch("zigdown-wasm.wasm"), importObject));

    wasm.renderToHtml(placeholder_markdown);

    let input = document.getElementById("input_box");
    input.addEventListener("input", renderFromInput, false);
}

bootstrap();
