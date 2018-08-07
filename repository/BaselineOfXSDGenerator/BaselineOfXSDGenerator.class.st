Class {
	#name : #BaselineOfXSDGenerator,
	#superclass : #BaselineOf,
	#category : #BaselineOfXSDGenerator
}

{ #category : #baselines }
BaselineOfXSDGenerator >> baseline: spec [
	<baseline>
	spec
		for: #common
		do: [ spec
				baseline: 'OPUMLXMI'
				with: [ spec repository: 'github://openponk/uml-xmi/repository' ].
			spec
				baseline: 'ChangesBuilder'
				with: [ spec repository: 'github://peteruhnak/pharo-changes-builder/repository' ].
			spec
				baseline: 'UMLMetamodel'
				with: [ spec repository: 'github://OpenPonk/uml-metamodel/repository' ].
			spec
				baseline: 'UMLBootstrapGenerator'
				with: [ spec repository: 'github://OpenPonk/uml-bootstrap-generator/repository' ].
			spec
				package: 'XSD-Metamodel-Generator'
				with: [ spec requires: #('OPUMLXMI' 'ChangesBuilder' 'UMLMetamodel' 'UMLBootstrapGenerator') ].
			spec group: 'default' with: #('XSD-Metamodel-Generator') ]
]
