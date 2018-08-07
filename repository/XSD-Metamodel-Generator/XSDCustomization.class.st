Class {
	#name : #XSDCustomization,
	#superclass : #Object,
	#category : #'XSD-Metamodel-Generator-Customizations'
}

{ #category : #accessing }
XSDCustomization >> supportedClasses [
	^ {self className withoutSuffix: 'Customization'}
]

{ #category : #accessing }
XSDCustomization >> supportsClass: aClassName [
	^ self className = (aClassName , #Customization)
]
