SILENCE_CONSOLE = "console.debug = function() {}; console.info = function() {}; console.error = function() {}; console.log = function() {};\n"

LOOP_MAX_ITERATIONS = 5000

editor = ace.edit "editor"
analysis = ace.edit "analysis"

editor.setTheme "ace/theme/monokai"
editor.getSession().setMode "ace/mode/javascript"

analysis.setReadOnly true
analysis.setShowPrintMargin false
analysis.renderer.setShowGutter false
analysis.setHighlightActiveLine false

# *************************************************************************************************
verifyHalts = (code, timeout, callback) ->
	blob = new Blob [SILENCE_CONSOLE + code + "\npostMessage();"], type: "application/javascript"
	worker = new Worker URL.createObjectURL blob
	
	workerTimer = setTimeout ->
		worker.terminate.call worker
		callback false
	, timeout

	worker.onmessage = ->
		clearTimeout workerTimer
		callback true

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

countIterations = (rootNode, block, source) ->
	modifiedCode = "var __jsPlaygroundCount__ = 0;
					#{source.substring(0, block.body.range[0] + 1)}
					__jsPlaygroundCount__++;
					#{source.substring(block.body.range[0] + 1, source.length)}
					__jsPlaygroundCount__;"

	console.log modifiedCode
	# worker = new Worker "data:text/javascript;base64,#{btoa(modifiedCode)}"
	# blob = new Blob [modifiedCode], type: "application/javascript"
	# worker = new Worker URL.createObjectURL blob
	
	# workerTimer = setTimeout worker.terminate, LOOP_TIMEOUT
	# worker.onmessage = (event) ->
	# 	clearInterval workerTimer
	# 	callback event.data

	tryEval modifiedCode
	# console.log modifiedCode

countCalls = (rootNode, block, source) ->
	modifiedCode = "var __jsPlaygroundCount__ = 0;
						#{source.substring(0, block.body.range[0] + 1)}
						__jsPlaygroundCount__++;
						#{source.substring(block.body.range[0] + 1, source.length)}
						__jsPlaygroundCount__;"
	# console.log(modifiedCode)
	
	# try
	# 	tryEval modifiedCode
	# catch error
	# 	console.log(error)
	# 	return -1

	tryEval modifiedCode

parse = (rootNode, source) ->
	codeAnalysis = []

	for node in rootNode.body
		# console.log JSON.stringify node, null, 4
		# console.log "\n"
		switch node.type
			when "ExpressionStatement"
				switch node.expression.type
					when "AssignmentExpression"
						vars = []
						tryEval "#{source[node.expression.range[0]...node.expression.range[1]]}"
						vars.push
							name: node.expression.left.name
							value: tryEval "JSON.stringify(#{node.expression.left.name})"
							type: tryEval "typeOf(#{node.expression.left.name})"
						
						analysisChunk = {}
						analysisChunk.line = node.expression.loc.start.line
						analysisChunk.vars = vars

						codeAnalysis.push analysisChunk

					when "SequenceExpression"
						vars = []
						for e in node.expression.expressions
							switch e.type
								when "AssignmentExpression"
									tryEval "#{source[e.range[0]...e.range[1]]}"
									vars.push
										name: e.left.name
										value: tryEval "JSON.stringify(#{e.left.name})"
										type: tryEval "typeOf(#{e.left.name})"

						analysisChunk = {}
						analysisChunk.line = node.expression.loc.start.line
						analysisChunk.vars = vars

						codeAnalysis.push analysisChunk

					when "UpdateExpression"
						vars = []
						tryEval "#{source[node.expression.range[0]...node.expression.range[1]]}"
						vars.push
							name: node.expression.argument.name
							value: tryEval "JSON.stringify(#{node.expression.argument.name})"
							type: tryEval "typeOf(#{node.expression.argument.name})"
						
						analysisChunk = {}
						analysisChunk.line = node.expression.loc.start.line
						analysisChunk.vars = vars

						codeAnalysis.push analysisChunk

					when "CallExpression"
						if node.expression.callee.object?.name is "console" and node.expression.callee.property.name in ["debug", "info", "error", "log"]
								for arg in node.expression.arguments
									codeAnalysis.push
										line: node.expression.loc.start.line
										raw: "=> #{tryEval("#{source[arg.range[0]...arg.range[1]]}").toString()}"
						else
							analysisChunk = {}
							analysisChunk.line = node.expression.loc.start.line

							returnVal = tryEval "#{source[node.expression.range[0]...node.expression.range[1]]};"
							analysisChunk.raw = "-> #{returnVal}: #{typeOf returnVal}"

							codeAnalysis.push analysisChunk

					else
						analysisChunk = {}
						analysisChunk.line = node.expression.loc.start.line

						returnVal = tryEval "#{source[node.expression.range[0]...node.expression.range[1]]};"
						analysisChunk.raw = "-> #{returnVal}: #{typeOf returnVal}"

						codeAnalysis.push analysisChunk

			when "VariableDeclaration"
				vars = []
				for d in node.declarations
					tryEval "#{source[d.range[0]...d.range[1]]}"
					vars.push
						name: d.id.name
						value: tryEval "JSON.stringify(#{d.id.name})"
						type: tryEval "typeOf(#{d.id.name})"

				analysisChunk = {}
				analysisChunk.line = node.loc.start.line
				analysisChunk.vars = vars

				codeAnalysis.push analysisChunk

			when "FunctionDeclaration"
				vars = []
				calls = countCalls rootNode, node, source
				# console.log(typeOf calls)
				# console.log(calls)
				tryEval "#{source[node.range[0]...node.range[1]]}"
				vars.push
					name: node.id.name + if typeOf calls is "Number" then " (#{calls} calls)" else " (#{calls})"
					type: tryEval "typeOf(#{node.id.name})"

				analysisChunk = {}
				analysisChunk.line = node.loc.start.line
				analysisChunk.vars = vars

				codeAnalysis.push analysisChunk

			when "ForStatement", "WhileStatement"
				recreateSandbox()

				vars = []
				iterations = countIterations rootNode, node, source
				vars.push
					name: "(#{iterations} times)"
					type: node.type

				analysisChunk = {}
				analysisChunk.line = node.loc.start.line
				analysisChunk.vars = vars

				codeAnalysis.push analysisChunk

				codeAnalysis.push parse(node.body, source)...

	codeAnalysis

updateAnalysis = ->
	recreateSandbox()

	source = editor.getValue()
	verifyHalts source, 1000, (halted) ->
		if halted
			tree = esprima.parse source,
				loc: true
				range: true

			# console.log JSON.stringify tree, null, 4
			# console.log "\n"

			codeAnalysis = parse tree, source

			lines = []
			for chunk in codeAnalysis
				chunkString = ""
				if chunk.raw?
					chunkString += chunk.raw
				if chunk.vars?
					chunkString += ("#{v.name}: #{v.type} #{if v.value? then "= #{v.value}" else ""}" for v in chunk.vars).join ", "

				lines[chunk.line - 1] = [] unless lines[chunk.line - 1]?
				lines[chunk.line - 1].push chunkString

			analysisText = ""
			for line in lines
				analysisText += line.join " | " if line?
				analysisText += "\n"

			analysis.setValue analysisText
		else
			analysis.setValue "ERROR: Code does not halt"

updateAnalysis()
editor.on "change", -> setTimeout updateAnalysis, 1000