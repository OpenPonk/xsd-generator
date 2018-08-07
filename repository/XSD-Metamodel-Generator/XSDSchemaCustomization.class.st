Class {
	#name : #XSDSchemaCustomization,
	#superclass : #XSDCustomization,
	#category : #'XSD-Metamodel-Generator-Customizations'
}

{ #category : #accessing }
XSDSchemaCustomization >> elementDeclarations [
	^ self contents select: [ :each | each oclIsKindOf: 'ElementDeclaration' ]
]

{ #category : #accessing }
XSDSchemaCustomization >> typeDefinitions [
	^ (((self contents
		select: [ :each | (each oclIsKindOf: 'Import') or: [ each oclIsKindOf: 'Include' ] ])
		flatCollect: [ :each | each resolvedSchema typeDefinitions ])
		, (self contents select: [ :each | each oclIsKindOf: 'TypeDefinition' ])) asSet asArray
]
