Class {
	#name : #XSDAttributeUseCustomization,
	#superclass : #XSDCustomization,
	#category : #'XSD-Metamodel-Generator-Customizations'
}

{ #category : #accessing }
XSDAttributeUseCustomization >> attributeDeclaration [
	^ self content
]
