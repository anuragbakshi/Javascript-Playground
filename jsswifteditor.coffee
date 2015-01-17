editor = ace.edit "editor"
analysis = ace.edit "analysis"

editor.setTheme "ace/theme/monokai"
editor.getSession().setMode "ace/mode/javascript"

analysis.setReadOnly true
analysis.setShowPrintMargin false
analysis.renderer.setShowGutter false
analysis.setHighlightActiveLine false

# *************************************************************************************************
parse = (rootNode, source) ->
	codeAnalysis = []

	for node in rootNode.body
		# console.log JSON.stringify node, null, 4
		# console.log "\n"
		switch node.type
			when "ExpressionStatement"
				switch node.expression.type
					when "AssignmentExpression"
						vars = {}
						vars[node.expression.left.name] = eval "#{source[node.expression.range[0]...node.expression.range[1]]}; JSON.stringify(#{node.expression.left.name})"
						
						analysisChunk = {}
						analysisChunk.line = node.expression.loc.start.line
						analysisChunk.vars = vars

						codeAnalysis.push analysisChunk

					when "SequenceExpression"
						vars = {}
						for e in node.expression.expressions
							switch e.type
								when "AssignmentExpression"
									vars[e.left.name] = eval "#{source[e.range[0]...e.range[1]]}; JSON.stringify(#{e.left.name})"
						
						analysisChunk = {}
						analysisChunk.line = node.expression.loc.start.line
						analysisChunk.vars = vars

						codeAnalysis.push analysisChunk

					when "CallExpression"
						returnVal = eval "#{source[node.expression.range[0]...node.expression.range[1]]};"
						console.log returnVal

			when "VariableDeclaration"
				vars = {}
				for d in node.declarations
					vars[d.id.name] = eval "#{source[d.range[0]...d.range[1]]}; JSON.stringify(#{d.id.name})"

				analysisChunk = {}
				analysisChunk.line = node.loc.start.line
				analysisChunk.vars = vars

				codeAnalysis.push analysisChunk

			when "FunctionDeclaration"
				eval "#{source[node.range[0]...node.range[1]]}"

	codeAnalysis

updateAnalysis = ->
	source = editor.getValue()
	tree = esprima.parse source,
		loc: true
		range: true

	codeAnalysis = parse tree, source

	lines = []
	for chunk in codeAnalysis
		line = ""
		if chunk.vars?
			line += ("#{name} = #{val}" for name, val of chunk.vars).join ", "

		lines[chunk.line - 1] = line

	analysisText = ""
	for l in lines
		if l?
			analysisText += l
		
		analysisText += "\n"

	analysis.setValue analysisText

updateAnalysis()
editor.on "change", -> setTimeout updateAnalysis, 100