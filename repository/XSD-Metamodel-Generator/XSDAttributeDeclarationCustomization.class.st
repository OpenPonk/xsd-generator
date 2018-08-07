Class {
	#name : #XSDAttributeDeclarationCustomization,
	#superclass : #XSDCustomization,
	#category : #'XSD-Metamodel-Generator-Customizations'
}

{ #category : #accessing }
XSDAttributeDeclarationCustomization >> attributeDeclaration [
	"<type: 'XSDAttributeDeclaration'>"
	^ self content
]
