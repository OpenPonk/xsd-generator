Class {
	#name : #XSDMetamodelGenerator,
	#superclass : #Object,
	#instVars : [
		'classPrefix',
		'packageName',
		'rootClassName',
		'sourceModel',
		'classes',
		'defaultValues'
	],
	#category : #'XSD-Metamodel-Generator-Generators'
}

{ #category : #translating }
XSDMetamodelGenerator class >> generate [
	<script>
	| generator model |
	Smalltalk globals
		at: #OntoUMLProfileFactory
		ifPresent: [ :factory | 
			model := factory profile.
			generator := self new.
			generator sourceModel: model.
			generator classPrefix: model implementationPrefix.
			generator packageName: model implementationPackage.
			(CBChangesBrowser changes: generator generateAll) open ]
]

{ #category : #'generating - methods' }
XSDMetamodelGenerator >> addAccessingDelegationMethodsFrom: aClassModel to: aClass [
	| redefinedNames |
	redefinedNames := Set new.
	aClassModel ownedAttributes
		ifNotNil: [ :attrs | 
			attrs
				select: [ :attr | attr redefinedProperties isNotNil ]
				thenDo: [ :attr | 
					redefinedNames
						addAll: (attr redefinedProperties collect: [ :prop | self attributeNameFor: prop ]) ] ].
	(self allSuperclassesOf: aClassModel)
		do: [ :superClassModel | 
			| superClass methods |
			superClass := classes at: superClassModel name.
			methods := (superClass methods select: [ :method | method protocol = 'accessing' ])
				reject: [ :method | 
					(redefinedNames includes: method selector)
						or: [ redefinedNames includes: (method selector withoutSuffix: ':') asSymbol ] ].
			methods
				do: [ :method | 
					| delegateMethod node comment |
					node := RBParser parseMethod: method source lines first.
					comment := self
						attributeTypeDeclarationFor: (superClassModel  ownedAttributes detect: [ :each | each name = (node selector withoutSuffix: ':') ]).
					delegateMethod := node numArgs = 0
						ifTrue: [ CBMethod new
								getter: node selector
									delegateFrom: '(sharedGeneralizations at: #' , (superClass name withoutPrefix: self classPrefix) , ')';
								protocol: 'accessing - ' , (superClass name withoutPrefix: self classPrefix) ]
						ifFalse: [ CBMethod new
								setter: (node selector withoutSuffix: ':')
									argument: ((node argumentNames first withoutPrefix: 'a') withoutPrefix: 'n')
									delegateTo: '(sharedGeneralizations at: #' , (superClass name withoutPrefix: self classPrefix) , ')'
									comment: comment;
								protocol: 'accessing - ' , (superClass name withoutPrefix: self classPrefix) ].
					aClass addMethod: delegateMethod ] ]
]

{ #category : #'generating - attributes' }
XSDMetamodelGenerator >> addAttribute: anAttributeModel to: aClass [
	| name comment getterBuilder |
	name := self attributeNameFor: anAttributeModel.
	comment := self attributeTypeDeclarationFor: anAttributeModel.
	aClass addInstVarNamed: name.
	(getterBuilder := OPUMLBootstrapGetterMethodBuilder new)
		selector: name;
		comment: comment.
	(self isLiteralSpecification: anAttributeModel defaultValue)
		ifTrue: [ getterBuilder defaultValue: (self defaultValueFrom: anAttributeModel defaultValue) ].
	(self isEnumValue: anAttributeModel defaultValue)
		ifTrue: [ getterBuilder defaultValue: (self defaultValueFrom: anAttributeModel defaultValue) ].
	self class environment
		at: (aClass name , 'Customization') asSymbol
		ifPresent: [ :cls | 
			(cls includesSelector: anAttributeModel name asSymbol)
				ifTrue: [ | getter |
					getter := CBMethod new
						protocol: 'accessing';
						source:
							('<1s>
	"<2s>"
	<3s>'
								expandMacrosWith: anAttributeModel name
								with: (CBMethod new asComment: comment)
								with: (cls >> anAttributeModel name asSymbol) ast body formattedCode).
					aClass addMethod: getter ]
				ifFalse: [ aClass addMethod: getterBuilder build ] ]
		ifAbsent: [ aClass addMethod: getterBuilder build ].
	self addSetterFor: anAttributeModel to: aClass
]

{ #category : #'generating - classes' }
XSDMetamodelGenerator >> addCommentFrom: aClassModel to: aClass [
	aClassModel ownedComments ifEmpty: [ ^ self ].
	aClass comment: aClassModel ownedComments first body
]

{ #category : #'generating - methods' }
XSDMetamodelGenerator >> addDelegationMethodsFrom: aClassModel to: aClass [
	self addAccessingDelegationMethodsFrom: aClassModel to: aClass.
	self addOperationsDelegationMethodsFrom: aClassModel to: aClass
]

{ #category : #'generating - enums' }
XSDMetamodelGenerator >> addEnumLiteral: anEnumLiteral to: aClass [
	| builder prohibitedClassSideSelectors |
	builder := CBMethodBuilder new.
	builder selector: anEnumLiteral name.
	anEnumLiteral ownedComments
		ifNotEmpty: [ :comments | builder addLine: '"' , (comments first body copyReplaceAll: '"' with: '""') , '"' ].
	builder addLine: '^ self on: #' , anEnumLiteral name.
	aClass
		addMethod:
			(CBMethod new
				protocol: 'accessing - enum';
				source: builder source).
	prohibitedClassSideSelectors := #(package).
	(prohibitedClassSideSelectors includes: anEnumLiteral name)
		ifFalse: [ self
				assert: [ (XSDEnum class canUnderstand: anEnumLiteral name) not ]
				description: 'Will not override class-side system methods'.
			aClass
				addMetaMethod:
					(CBMethod new
						protocol: 'accessing - enum';
						source: builder source) ]
]

{ #category : #'generating - methods' }
XSDMetamodelGenerator >> addGeneralizationsFrom: aClassModel to: cls [
	| sharedMethod directMethod |
	sharedMethod := CBMethodBuilder new.
	sharedMethod selector: 'initializeSharedGeneralizations'.
	(self allSuperclassesOf: aClassModel)
		do: [ :each | 
			sharedMethod
				addLine:
					('sharedGeneralizations at: #<1s> put: (<2s> newOnShared: sharedGeneralizations).'
						expandMacrosWith: ((self classNameFor: each name) withoutPrefix: self classPrefix)
						with: (self classNameFor: each name)) ].
	sharedMethod addLine: 'sharedGeneralizations at: #' , (aClassModel name withoutPrefix: self classPrefix) , ' put: self.'.
	directMethod := CBMethodBuilder new.
	directMethod selector: 'initializeDirectGeneralizations'.
	directMethod addLine: 'directGeneralizations := {'.
	directMethod addIndent.
	aClassModel superClasses
		reject: [ :each | each name = 'Element' ]
		thenDo: [ :each | 
			directMethod
				addLine:
					'sharedGeneralizations at: #'
						, ((self classNameFor: each name) withoutPrefix: self classPrefix) , '.' ].
	directMethod removeIndent.
	directMethod addLine: '}'.
	cls compile: sharedMethod source trimmed classified: 'initialization'.
	cls compile: directMethod source trimmed classified: 'initialization'
]

{ #category : #'generating - operations' }
XSDMetamodelGenerator >> addOperation: anOperationModel to: aClass [
	self addStubOperation: anOperationModel to: aClass.
	(anOperationModel method isNotNil and: [ anOperationModel method isNotEmpty ])
		ifTrue: [ self addRealOperation: anOperationModel to: aClass ]
]

{ #category : #'generating - methods' }
XSDMetamodelGenerator >> addOperationsDelegationMethodsFrom: aClassModel to: aClass [
	| redefinedNames |
	redefinedNames := Set new.
	aClassModel ownedOperations
		ifNotNil:
			[ :ops | ops select: [ :op | op method isNotNil ] thenDo: [ :op | redefinedNames add: op name ] ].
	(self allSuperclassesOf: aClassModel)
		do: [ :superClassModel | 
			| superClass methods |
			superClass := classes at: superClassModel name.
			methods := (superClass methods select: [ :method | method protocol = 'operations' ])
				reject: [ :method | 
					(redefinedNames includes: method selector)
						or: [ redefinedNames includes: (method selector withoutSuffix: ':') asSymbol ] ].
			methods
				do: [ :method | 
					| delegateMethod node |
					node := RBParser parseMethod: method source lines first.
					delegateMethod := CBMethod new
						getter: node selector
							delegateFrom: '(sharedGeneralizations at: #' , (superClass name withoutPrefix: self classPrefix) , ')';
						protocol: 'operations - ' , (superClass name withoutPrefix: self classPrefix).
					aClass addMethod: delegateMethod ] ]
]

{ #category : #'generating - operations' }
XSDMetamodelGenerator >> addRealOperation: anOperationModel to: aClass [
	| name comment methodBuilder |
	name := self operationNameFor: anOperationModel.
	comment := self commentIn: anOperationModel.
	methodBuilder := CBMethodBuilder new selector: name.
	methodBuilder addComment: comment.
	methodBuilder addLine: ''.
	anOperationModel precondition
		ifNotNil: [ anOperationModel precondition
				do: [ :pre | 
					methodBuilder
						addComment: pre name , ': {' , pre specification language first , '} ' , pre specification body first ] ].
	anOperationModel bodyCondition
		ifNotNil: [ :bodyCond | 
			| spec |
			spec := bodyCond specification.
			spec body
				withIndexDo: [ :each :i | methodBuilder addComment: '{' , (spec language at: i) , '} ' , each ] ].
	methodBuilder addLine: ''.
	methodBuilder
		addLine: (self prefixClassNamesInText: anOperationModel method first body first).
	aClass compile: methodBuilder source classified: 'operations'
]

{ #category : #'generating - attributes' }
XSDMetamodelGenerator >> addSetterFor: anAttributeModel to: aClass [
	| name comment oppositeEnd setter argumentGuard oneGuard zeroOneGuard manyGuard basicOneGuard basicZeroOneGuard basicManyGuard typeMap typeName |
	name := self attributeNameFor: anAttributeModel.
	oppositeEnd := anAttributeModel opposite.
	self assert: [ oppositeEnd isNil ].
	self assert: [ anAttributeModel isDerived not ].
	oneGuard := '{argument} oclIsKindOf: ''{type}'''.
	zeroOneGuard := '{argument} isNil or: [ {argument} oclIsKindOf: ''{type}'' ]'.
	manyGuard := '{argument} allSatisfy: [ :each | each oclIsKindOf: ''{type}'' ]'.
	basicOneGuard := '{argument} isKindOf: {type}'.
	basicZeroOneGuard := '{argument} isNil or: [ {argument} isKindOf: {type} ]'.
	basicManyGuard := '{argument} allSatisfy: [ :each | each isKindOf: {type} ]'.
	comment := self attributeTypeDeclarationFor: anAttributeModel.
	typeMap := {'DOMAttr' -> #XMLAttribute.
	'DOMDocument' -> #XMLDocument.
	'DOMElement' -> #XMLElement.
	'DOMNode' -> #XMLNode.
	'Value' -> #Object} asDictionary.
	typeName := anAttributeModel type name.
	((typeName beginsWith: 'XSD') and: [ anAttributeModel type oclIsKindOf: 'Class' ])
		ifTrue: [ typeName := typeName withoutPrefix: 'XSD'.
			anAttributeModel isMultivalued
				ifTrue: [ argumentGuard := manyGuard ]
				ifFalse: [ anAttributeModel lower = 0
						ifTrue: [ argumentGuard := zeroOneGuard ]
						ifFalse: [ argumentGuard := oneGuard ] ] ]
		ifFalse: [ typeMap at: typeName ifPresent: [ :mappedType | typeName := mappedType ].
			self assert: [ Smalltalk globals includesKey: typeName asSymbol ].
			anAttributeModel isMultivalued
				ifTrue: [ argumentGuard := basicManyGuard ]
				ifFalse: [ anAttributeModel lower = 0
						ifTrue: [ argumentGuard := basicZeroOneGuard ]
						ifFalse: [ argumentGuard := basicOneGuard ] ] ].
	self assert: [ argumentGuard isNotNil ].
	argumentGuard := argumentGuard
		format:
			{'argument' -> (CBMethod basicNew asArgumentName: anAttributeModel type name).
			'type' -> typeName} asDictionary.
	setter := CBTemplateMethodBuilder new.
	setter useFormat.
	setter protocol: 'accessing'.
	setter
		template:
			'{name}: {argument}
	"{comment}"
	self assert: [ {argumentGuard} ].
	{name} := {argument}'.
	aClass
		addMethod:
			(setter
				methodOn:
					{'name' -> name.
					'argument' -> (CBMethod basicNew asArgumentName: anAttributeModel type name).
					'comment' -> (CBMethod basicNew asComment: comment).
					'argumentGuard' -> argumentGuard} asDictionary)
]

{ #category : #'generating - operations' }
XSDMetamodelGenerator >> addStubOperation: anOperationModel to: aClass [
	| name comment methodBuilder |
	name := self stubOperationNameFor: anOperationModel.
	comment := self commentIn: anOperationModel.
	methodBuilder := CBMethodBuilder new selector: name.
	methodBuilder addComment: comment.
	methodBuilder addLine: ''.
	anOperationModel precondition
		ifNotNil: [ anOperationModel precondition
				do: [ :pre | 
					methodBuilder
						addComment: pre name , ': {' , pre specification language first , '} ' , pre specification body first ] ].
	anOperationModel bodyCondition
		ifNotNil: [ :bodyCond | 
			| spec |
			spec := bodyCond specification.
			spec body
				withIndexDo: [ :each :i | methodBuilder addComment: '{' , (spec language at: i) , '} ' , each ] ].
	methodBuilder addLine: ''.
	methodBuilder addLine: 'self notYetImplemented'.
	aClass compile: methodBuilder source withSqueakLineEndings classified: 'operations - stubs'
]

{ #category : #retrieving }
XSDMetamodelGenerator >> allClassesInModel [
	^ self sourceModel ownedTypes select: [ :each | each oclIsKindOf: #Class ]
]

{ #category : #retrieving }
XSDMetamodelGenerator >> allSuperclassesOf: aClassModel [
	| generalizations |
	generalizations := OrderedCollection new.
	(self superclassLayersOf: aClassModel)
		do: [ :layer | layer do: [ :each | generalizations addIfNotPresent: each ] ].
	generalizations removeAllSuchThat: [ :each | each name = 'Element' ].
	^ generalizations asArray
]

{ #category : #utility }
XSDMetamodelGenerator >> asPlural: aString [
	(aString endsWith: 's')
		ifTrue: [ ^ aString , 'es' ].
	(aString endsWith: 'y')
		ifTrue: [ ^ (aString withoutSuffix: 'y') , 'ies' ].
	^ aString , 's'
]

{ #category : #retrieving }
XSDMetamodelGenerator >> attributeNameFor: anAttributeModel [
	| name |
	name := anAttributeModel name.
	"class is a prohibited method name (it accesses the class-side)"
	name = 'class'
		ifTrue: [ name := 'owningClass' ].
	^ name
]

{ #category : #'generating - attributes' }
XSDMetamodelGenerator >> attributeTypeDeclarationFor: anAttributeModel [
	^ String
		streamContents: [ :stream | 
			stream << '<'.
			stream << 'type: '''.
			stream << anAttributeModel type name.
			stream << ''''.
			(anAttributeModel lower = anAttributeModel upper and: [ anAttributeModel lower = 1 ])
				ifFalse: [ stream << ' multiplicity: '''.
					stream << anAttributeModel lower asString.
					anAttributeModel lower = anAttributeModel upper
						ifFalse: [ stream << '..'.
							stream << anAttributeModel upper asString ].
					stream << '''' ].
			anAttributeModel isComposite
				ifTrue: [ stream << ' aggregation: '''.
					stream << anAttributeModel aggregation.
					stream << '''' ].
			stream << '>' ]
]

{ #category : #changes }
XSDMetamodelGenerator >> changes [
	| changeSet |
	changeSet := CBChangeSet new.
	classes do: [ :each | changeSet addClass: each ].
	^ changeSet refactoringChanges
]

{ #category : #retrieving }
XSDMetamodelGenerator >> classNameFor: aString [
	^ (self classPrefix , (aString withoutPrefix: self classPrefix)) asSymbol
]

{ #category : #accessing }
XSDMetamodelGenerator >> classPrefix [
	^ classPrefix
]

{ #category : #accessing }
XSDMetamodelGenerator >> classPrefix: anObject [
	classPrefix := anObject
]

{ #category : #accessing }
XSDMetamodelGenerator >> classes [
	^ classes
]

{ #category : #accessing }
XSDMetamodelGenerator >> classes: anObject [
	classes := anObject
]

{ #category : #retrieving }
XSDMetamodelGenerator >> commentIn: anElement [
	^ (anElement ownedComments isNil or: [ anElement ownedComments isEmpty ])
		ifTrue: [ '' ]
		ifFalse: [ anElement ownedComments first body ]
]

{ #category : #'generating - classes' }
XSDMetamodelGenerator >> createClassFrom: aClassModel in: aCategoryName [
	| cls |
	cls := self ensureCreateClass: aClassModel name in: aCategoryName.
	aClassModel ownedAttributes
		ifNotNil: [ :attrib | attrib do: [ :each | self addAttribute: each to: cls ] ].
	aClassModel ownedOperations
		ifNotNil: [ :ops | ops do: [ :each | self addOperation: each to: cls ] ].
	"	aClassModel ownedRule do: [ :each | self addRule: each to: cls ]."
	self addGeneralizationsFrom: aClassModel to: cls.
	self addCommentFrom: aClassModel to: cls.
	^ cls
]

{ #category : #'generating - meta' }
XSDMetamodelGenerator >> createElementMeta [
	"| cls sourceClass |
	cls := self ensureCreateClass: 'MetaElement' in: 'Meta'.
	cls
		comment:
			'I am a metaclass for UML classes implementing some behavior for managing the classes and other stuff (like an announcer).'.
	sourceClass := OPUMLMetamodelElementTemplate.
	sourceClass instanceVariables do: [ :each | cls addInstVarNamed: each ].
	sourceClass class instanceVariables do: [ :each | cls addMetaInstVarNamed: each ].
	sourceClass methods
		do: [ :each | 
			cls
				addMethod:
					(CBMethod new
						source: each sourceCode;
						protocol: each protocol) ].
	sourceClass class methods
		do: [ :each | 
			cls
				addMetaMethod:
					(CBMethod new
						source: each sourceCode;
						protocol: each protocol) ].
	^ cls"
]

{ #category : #'generating - enums' }
XSDMetamodelGenerator >> createEnumFrom: anEnumModel in: aCategoryName [
	| cls |
	cls := self ensureCreateClass: anEnumModel name in: aCategoryName.
	cls parent: 'XSDEnum'.
	self addCommentFrom: anEnumModel to: cls.
	anEnumModel ownedLiterals
		ifNotNil: [ :lits | lits do: [ :each | self addEnumLiteral: each to: cls ] ].
	^ cls
]

{ #category : #'generating - packages' }
XSDMetamodelGenerator >> createTargetPackage [
	(RPackage organizer includesPackageNamed: self packageName)
		ifFalse: [ RPackage organizer createPackageNamed: self packageName ]
]

{ #category : #retrieving }
XSDMetamodelGenerator >> defaultValueFrom: aDefaultValue [
	(self isEnumValue: aDefaultValue)
		ifTrue: [ ^ (self classNameFor: aDefaultValue type name) , ' new ' , aDefaultValue instance name ].
	aDefaultValue value ifNotNil: [ ^ aDefaultValue value ].
	^ self defaultValues
		detect: [ :pair | aDefaultValue className endsWith: pair key ]
		ifFound: [ :pair | pair value ]
		ifNone: [ nil ]
]

{ #category : #retrieving }
XSDMetamodelGenerator >> defaultValues [
	| literals |
	"	defaultValues ifNotNil: [ ^ defaultValues ]."
	literals := (sourceModel packagedElement detect: [ :each | each name = 'Values' ])
		packagedElement select: [ :each | each name beginsWith: 'Literal' ].
	defaultValues := literals
		collect: [ :each | 
			| key value |
			key := each name.
			value := each ownedAttribute
				ifNil: [ nil ]
				ifNotNil: [ (each ownedAttribute detect: [ :attr | attr name = 'value' ]) defaultValue value ].
			key -> value ].
	^ defaultValues
]

{ #category : #'generating - classes' }
XSDMetamodelGenerator >> ensureCreateClass: aName in: aTagName [
	^ classes
		at: aName
		ifAbsentPut: [ CBClass
				name: (self classNameFor: aName)
				parent: (self parentFor: aName)
				package: self packageName , '-Model' ]
]

{ #category : #generating }
XSDMetamodelGenerator >> generate [
	<script: 'self new generate'>
	| contents xmi uml generator changes |
	contents := 'D:\tmp\XSD.emof'
		asFileReference contents.
	xmi := OPXMIReader readFrom: contents.
	uml := OPUMLXMIReader new readXmi: xmi.
	classes := uml ownedTypes select: [ :each | each oclIsKindOf: #Class ].
	classes
		do: [ :cls | 
			cls ownedAttributes
				do: [ :attr | 
					| mul |
					mul := (attr readSlotNamed: #sharedGeneralizations) at: #MultiplicityElement.
					(mul readSlotNamed: #lower)
						ifNotNil: [ :lower | mul lowerValue: (OPUMLLiteralInteger new value: lower) ].
					(mul readSlotNamed: #upper)
						ifNotNil: [ :upper | mul upperValue: (OPUMLLiteralUnlimitedNatural new value: upper) ] ] ].
	generator := XSDMetamodelGenerator new.
	generator sourceModel: uml.
	generator classPrefix: 'XSD'.
	generator packageName: 'XSD-Metamodel'.
	changes := generator generateAll.
	(CBChangesBrowser changes: changes) open
]

{ #category : #generating }
XSDMetamodelGenerator >> generateAll [
	classes := Dictionary new.
	self loadTemplateMethods.
	self createTargetPackage.
	"	self createElementMeta."
	self generateAllEnums.
	self generateAllClasses.
	self generateAllDelegationMethods.
	^ self changes
]

{ #category : #generating }
XSDMetamodelGenerator >> generateAllClasses [
	self sourceModel ownedTypes
		select: [ :each | each oclIsKindOf: #Class ]
		thenDo: [ :each | self createClassFrom: each in: packageName , '-Model' ]
]

{ #category : #generating }
XSDMetamodelGenerator >> generateAllDelegationMethods [
	self allClassesInModel
		do: [ :each | self addDelegationMethodsFrom: each to: (classes at: each name) ]
]

{ #category : #generating }
XSDMetamodelGenerator >> generateAllEnums [
	self sourceModel ownedTypes
		select: [ :each | each oclIsKindOf: 'Enumeration' ]
		thenDo: [ :each | self createEnumFrom: each in: 'Enumerations' ]
]

{ #category : #generating }
XSDMetamodelGenerator >> generateExtensionMethods [
	| extensions metaClass cls extensionGetter extensionSetter |
	extensions := self sourceModel packagedElements
		select: [ :each | each oclIsKindOf: #Extension ].
	extensions
		do: [ :ext | 
			metaClass := self class environment
				at: ('OPUML' , ext ownedEnd opposite type name) asSymbol.
			cls := CBClass fromClass: metaClass.
			classes at: cls name put: cls.
			extensionGetter := CBMethod new
				source:
					('<1s>
		^ self tagAt: #<1s> ifAbsent: [ nil ]' expandMacrosWith: ext ownedEnd name);
				protocol: '*' , self sourceModel implementationPackage.
			extensionSetter := CBMethod new
				source:
					('<1s>: a<2s>
	| old<2s> |
	old<2s> := self <1s>.
	self tagAt: #<1s> put: a<2s>.
	OPUMLToOneLink
		on: self
		thisSelector: #<1s>
		otherSelector: #<3s>
		updateFrom: old<2s>
		to: a<2s>'
						expandMacrosWith: ext ownedEnd name
						with: ext ownedEnd type name
						with: ext ownedEnd opposite name);
				protocol: '*' , self sourceModel implementationPackage.
			cls addMethod: extensionGetter.
			cls addMethod: extensionSetter ]
]

{ #category : #initialization }
XSDMetamodelGenerator >> initialize [
	super initialize.
	classes := Dictionary new
]

{ #category : #testing }
XSDMetamodelGenerator >> isEnumValue: anElement [
	^ (anElement className endsWith: 'InstanceValue') and: [ anElement type className endsWith: 'Enumeration' ]
]

{ #category : #testing }
XSDMetamodelGenerator >> isLiteralSpecification: anElement [
	^ anElement isNotNil and: [ (anElement instVarNamed: #sharedGeneralizations) includesKey: #LiteralSpecification ]
]

{ #category : #generating }
XSDMetamodelGenerator >> loadTemplateMethods [
	| templateClasses allClasses |
	templateClasses := XSDCustomization allSubclasses.
	allClasses := self allClassesInModel.
	templateClasses
		do: [ :cls | 
			| supported template |
			template := cls new.
			supported := template supportedClasses.
			supported
				do: [ :name | 
					| classModel |
					classModel := allClasses detect: [ :each | each name = name ].
					classModel ownedOperations
						do: [ :op | op method: (template methodsFor: op inClassNamed: name) ] ] ]
]

{ #category : #retrieving }
XSDMetamodelGenerator >> operationNameFor: anOperationName [
	| name |
	name := anOperationName name.
	"class is a prohibited method name (it accesses the class-side)"
	name = 'class'
		ifTrue: [ name := 'owningClass' ].
	^ name
]

{ #category : #accessing }
XSDMetamodelGenerator >> packageName [
	^ packageName
]

{ #category : #accessing }
XSDMetamodelGenerator >> packageName: anObject [
	packageName := anObject
]

{ #category : #retrieving }
XSDMetamodelGenerator >> parentFor: aClassName [
	aClassName = 'MetaElement'
		ifTrue: [ ^ 'Object' ].
	aClassName = 'Element'
		ifTrue: [ ^ self classPrefix , 'MetaElement' ].
	^ self classPrefix , 'Element'
]

{ #category : #'generating - operations' }
XSDMetamodelGenerator >> prefixClassNamesInText: aString [
	^ aString
		copyWithRegex: '''%\w+%'''
		matchesTranslatedUsing: [ :each | self classPrefix , (each copyFrom: 3 to: each size - 2) ]
]

{ #category : #accessing }
XSDMetamodelGenerator >> sourceModel [
	^ sourceModel
]

{ #category : #accessing }
XSDMetamodelGenerator >> sourceModel: anObject [
	sourceModel := anObject
]

{ #category : #retrieving }
XSDMetamodelGenerator >> stubOperationNameFor: anOperationName [
	^ (self operationNameFor: anOperationName) , 'Stub'
]

{ #category : #retrieving }
XSDMetamodelGenerator >> superclassLayersOf: aClassModel [
	| subclasses layers layer parents |
	layers := OrderedCollection new.
	subclasses := OrderedCollection with: aClassModel.
	[ subclasses isNotEmpty ]
		whileTrue: [ layer := subclasses flatCollect: #superClasses.
			layers add: layer asArray.
			subclasses := layer ].
	^ layers reversed asArray
]
