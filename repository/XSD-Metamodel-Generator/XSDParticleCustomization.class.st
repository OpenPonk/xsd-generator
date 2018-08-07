Class {
	#name : #XSDParticleCustomization,
	#superclass : #XSDCustomization,
	#instVars : [
		'maxOccurs'
	],
	#category : #'XSD-Metamodel-Generator-Customizations'
}

{ #category : #accessing }
XSDParticleCustomization >> maxOccurs: anInteger [
	self assert: [ anInteger isNil or: [ anInteger isKindOf: Integer ] ].
	maxOccurs := anInteger
]
