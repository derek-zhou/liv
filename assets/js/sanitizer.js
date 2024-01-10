export {setup, sanitizeHtml, sanitizeText};

var iframe;
const attributeSet = new Set(['alt', 'height', 'href', 'type', 'src', 'width']);
const tagSet = new Set(['A', 'ABBR', 'ADDR', 'ARTICLE', 'ASIDE', 'AUDIO', 'B', 'BLOCKQUOTE',
			'BR', 'CAPTION', 'CITE', 'CODE', 'COL', 'COLGROUP', 'DD', 'DEL', 'DFN',
			'DIV', 'DL', 'DT', 'EM', 'FIGCAPTION', 'FIGURE', 'FOOTER', 'HEADER',
			'HGROUP', 'H1', 'H2', 'H3', 'H4', 'H5', 'H6', 'HR', 'I', 'IMG', 'INS',
			'LABEL', 'LI', 'LINK', 'MAIN', 'MARK', 'NAV', 'OL', 'P', 'PICTURE',
			'PRE', 'Q', 'S', 'SAMP', 'SECTION', 'SMALL', 'SOURCE', 'SPAN', 'STRONG',
			'SUB', 'SUP', 'SVG', 'TABLE', 'TBODY', 'TD', 'TFOOT', 'TH', 'THEAD',
			'TIME', 'TR', 'TRACK', 'U', 'UL', 'VIDEO', 'WBR']);

function setup(elem) {
    iframe = elem;
}

function sanitizeText(input) {
    var iframe_body = iframe.contentDocument.body;
    iframe_body.innerHTML = input;
    return iframe_body.textContent;
}

function sanitizeHtml(input) {
    var iframe_body = iframe.contentDocument.body;
    iframe_body.innerHTML = input;
    var sanitized = iframe.contentDocument.createElement('Body');
    sanitizeChildren(iframe_body, iframe.contentDocument, sanitized);
    return sanitized.innerHTML;
}

function sanitizeChildren(node, container, newNode) {
    for (let i = 0; i < node.childNodes.length; i++) {
	let subNode = sanitizeNode(node.childNodes[i], container);
	if (subNode)
            newNode.appendChild(subNode);
    }
}

function sanitizeAttributes(node, newNode) {
    for (let i = 0; i < node.attributes.length; i++) {
	let attr = node.attributes[i];
	if (attributeSet.has(attr.name) && attr.value.indexOf("javascript:") != 0)
	    newNode.setAttribute(attr.name, attr.value);
    }
}

function sanitizeNode(node, container) {
    if (node.nodeType == Node.TEXT_NODE) {
        return node.cloneNode(true);
    } else if (node.nodeType == Node.ELEMENT_NODE && tagSet.has(node.tagName)) {
	let newNode = container.createElement(node.tagName);
	sanitizeAttributes(node, newNode);
	sanitizeChildren(node, container, newNode);
	return newNode;
    }
}

