SILENCE_CONSOLE = "console.debug = function() {}; console.info = function() {}; console.error = function() {}; console.log = function() {};\n"

LOOP_MAX_ITERATIONS = 5000

# global namespace
window.__jsPlayground__ = {}

editor = ace.edit "editor"
analysis = ace.edit "analysis"
window.__jsPlayground__.editor = editor
window.__jsPlayground__.analysis = analysis

editor.setTheme "ace/theme/monokai"
editor.getSession().setMode "ace/mode/javascript"
editor.setFontSize 14
editor.renderer.setShowPrintMargin false

analysis.setTheme "ace/theme/monokai"
analysis.getSession().setMode "ace/mode/java"
analysis.setFontSize 14
analysis.setReadOnly true
analysis.setShowPrintMargin false
analysis.setHighlightActiveLine false
analysis.renderer.setShowGutter false
analysis.renderer.setShowPrintMargin false

verifyHalts = (code, timeout, callback) ->
	blob = new Blob ["#{SILENCE_CONSOLE}
					var ex;
					try {
						#{code}
					} catch(e) {
						ex = e;
					}
					if(ex !== undefined)
						postMessage(e.message);
					else
						postMessage();\n"], type: "application/javascript"
	
	worker = new Worker URL.createObjectURL blob
	
	workerTimer = setTimeout ->
		worker.terminate.call worker
		callback false
	, timeout

	worker.onmessage = (event) ->
		clearTimeout workerTimer
		callback true, event.data

tryEval = (code) ->
	try 
		sandbox.eval code
	catch error
		error

recreateSandbox = ->
	oldIframe = document.getElementById "sandbox-iframe"
	if oldIframe?
		document.body.removeChild oldIframe

	iframe = document.createElement "iframe"
	iframe.id = "sandbox-iframe"
	document.body.appendChild iframe

	window.sandbox = iframe.contentWindow
	tryEval "window.typeOf = #{typeOf.toString()}"
	tryEval "console.debug = function() {};
				console.info = function() {};
				console.error = function() {};
				console.log = function() {};"

typeOf = (obj) ->
	({}).toString.call(obj).match(/\s([a-zA-Z]+)/)[1]

countIterations = (block, source) ->
	modifiedCode = "var __jsPlaygroundCount__ = 0;
					#{source.substring(0, block.body.range[0] + 1)}
					__jsPlaygroundCount__++;
					#{source.substring(block.body.range[0] + 1, source.length)}
					__jsPlaygroundCount__;"

	tryEval modifiedCode

countCalls = (block, source) ->
	modifiedCode = "var __jsPlaygroundCount__ = 0;
					#{source.substring(0, block.body.range[0] + 1)}
					__jsPlaygroundCount__++;
					#{source.substring(block.body.range[0] + 1, source.length)}
					__jsPlaygroundCount__;"

	tryEval modifiedCode

resolveValues = (expression, source) ->
	modifiedCode = "var __jsPlaygroundValues__ = [];
					#{source.substring(0, expression.range[0])}
					(function() {
						var __jsPlaygroundTemp__ = #{source[expression.range[0]...expression.range[1]]};
						__jsPlaygroundValues__.push([__jsPlaygroundTemp__, typeOf(__jsPlaygroundTemp__)]);
						return __jsPlaygroundTemp__;
					})()
					#{source.substring(expression.range[1], source.length)}
					__jsPlaygroundValues__;"
	
	tryEval modifiedCode

processExpression = (expression, source, codeAnalysis) ->
	switch expression.type
		when "AssignmentExpression", "UpdateExpression"
			recreateSandbox()
			values = resolveValues expression, source

			vars = []
			for v in values
				vars.push
					name: (if expression.type is "AssignmentExpression" then expression.left else expression.argument).name
					value: v[0]
					type: v[1]
			
			analysisChunk =
				line: expression.loc.start.line
				vars: vars

			codeAnalysis.push analysisChunk

		when "SequenceExpression"
			recreateSandbox()
			for e in expression.expressions
				processExpression e, source, codeAnalysis

		else
			if expression.type is "CallExpression" and expression.callee.object?.name is "console" and expression.callee.property.name in ["debug", "info", "error", "log"]
				for arg in expression.arguments
					values = resolveValues arg, source
					for v in values
						codeAnalysis.push
							line: expression.loc.start.line
							raw: "=> \"#{v[0].toString()}\""
			else
				recreateSandbox()
				values = resolveValues expression, source

				for v in values
					codeAnalysis.push
						line: expression.loc.start.line
						raw: "-> #{v[0]}: #{v[1]}"

parse = (rootNode, source) ->
	codeAnalysis = []

	for node in rootNode.body
		switch node.type
			when "ExpressionStatement"
				processExpression node.expression, source, codeAnalysis

			when "VariableDeclaration"
				vars = []
				for d in node.declarations
					values = resolveValues d.init, source
					for v in values
						vars.push
							name: d.id.name
							value: v[0]
							type: v[1]

				codeAnalysis.push
					line: node.loc.start.line
					vars: vars

			when "FunctionDeclaration"
				vars = []
				calls = countCalls node, source
				tryEval "#{source[node.range[0]...node.range[1]]}"
				vars.push
					name: node.id.name + if typeOf calls is "Number" then " (#{calls} calls)" else " (#{calls})"
					type: tryEval "typeOf(#{node.id.name})"

				codeAnalysis.push
					line: node.loc.start.line
					vars: vars

			when "ForStatement", "WhileStatement"
				recreateSandbox()

				vars = []
				iterations = countIterations node, source
				vars.push
					name: "(#{iterations} times)"
					type: node.type

				codeAnalysis.push
					line: node.loc.start.line
					vars: vars

				codeAnalysis.push parse(node.body, source)...

	codeAnalysis

updateAnalysis = ->
	recreateSandbox()

	source = editor.getValue()
	verifyHalts source, 1000, (halted, exception) ->
		if halted
			if exception?
				console.log "hbsdjhbfgbs"
				analysis.setValue "ERROR: #{exception}", -1
			else
				tree = esprima.parse source,
					loc: true
					range: true

				codeAnalysis = parse tree, source

				lines = []
				for chunk in codeAnalysis
					chunkString = ""
					if chunk.raw?
						chunkString += chunk.raw
					if chunk.vars?
						chunkString += ("#{v.name}: #{v.type} #{if v.value? then "= #{v.value}" else ""}" for v in chunk.vars).join " | "

					lines[chunk.line - 1] = [] unless lines[chunk.line - 1]?
					lines[chunk.line - 1].push chunkString

				analysisText = ""
				for line in lines
					analysisText += line.join " | " if line?
					analysisText += "\n"

				analysis.setValue analysisText, -1
		else
			analysis.setValue "Error exists or code does not halt", -1

updateAnalysis()
editor.on "change", -> setTimeout updateAnalysis, 1000
editor.getSession().on "changeScrollTop", (scrollTop) -> analysis.getSession().setScrollTop scrollTop