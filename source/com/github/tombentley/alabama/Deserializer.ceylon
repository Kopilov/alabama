import ceylon.collection {
    ArrayList,
    HashMap
}
import ceylon.json {
    StringTokenizer,
    Positioned
}
import ceylon.json.stream {
    ArrayStartEvent,
    ArrayEndEvent,
    KeyEvent,
    ObjectStartEvent,
    ObjectEndEvent,
    StreamParser,
    BasicEvent
}
import ceylon.language.meta {
    type
}
import ceylon.language.meta.declaration {
    ValueDeclaration
}
import ceylon.language.meta.model {
    Class,
    Interface,
    UnionType,
    Type,
    ClassOrInterface,
    ClassModel
}
import ceylon.language.serialization {
    DeserializationContext,
    deser=deserialization
}

abstract class None() of none{}
object none extends None() {}


class S11nBuilder<Id>(DeserializationContext<Id> dc, clazz, id) 
        given Id satisfies Object{
    
    ClassModel<Object> clazz;
    Id id;
    
    shared void bindAttribute(String attributeName, Id attributeValue) {
        //print("bindAttribute(``attributeName``, ``attributeValue``) ``clazz``");
        assert(exists attr = clazz.getAttribute<Nothing,Anything>(attributeName)); 
        ValueDeclaration vd = attr.declaration;
        if (attributeName.startsWith("@")) {
            dc.attribute(id, vd, attributeValue);
        } else {
            // XXX I can't do this, because instantiate will have returned 
            // an actual instance and I need it's ID
            dc.attribute(id, vd, attributeValue);
        }
    }
    
    shared Id instantiate() {
        dc.instance(id, clazz);
        return id;
    }
    
}

"A contract for building collection-like things from JSON arrays."
interface S11nContainerBuilder<Id> {
    shared formal void addElement(Type<> et, Id element);
    shared formal Id instantiate(
        "A hint at the type originating from the metamodel"
        Type<> modelHint);
}

class S11nSequenceBuilder<Id>(DeserializationContext<Id> dc, id, Id nextId()) 
        satisfies S11nContainerBuilder<Id> {
    Id id;
    ArrayList<Id> elements = ArrayList<Id>(); 
    variable Type<Anything> elementType = `Nothing`;
    shared actual void addElement(Type<> et, Id element) {
        elements.add(element);
        elementType = et.union(elementType);
    }
    shared actual Id instantiate(
        "A hint at the type originating from the metamodel"
        Type<> modelHint) {
        //dc.instanceValue(id, elements.sequence());
        if (elements.empty) {
            dc.instanceValue(id, empty);
        } else {
            Id arrayId = nextId();
            dc.instance(arrayId, `class Array`.classApply<Anything,Nothing>(elementType));
            Id sizeId = nextId();
            dc.instanceValue(sizeId, elements.size);
            dc.attribute(arrayId, `value Array.size`, sizeId);
            variable value index = 0;
            for (e in elements) {
                dc.element(arrayId, index, e);
                index++;
            }
            
            dc.instance(id, `class ArraySequence`.classApply<Anything,Nothing>(elementType));
            
            dc.attribute(id, `class ArraySequence`.getDeclaredMemberDeclaration<ValueDeclaration>("array") else nothing, arrayId);
            
        }
        return id;
    }
}

"A [[ContainerBuilder]] for building [[Array]]s"
class S11nArrayBuilder<Id>(DeserializationContext<Id> dc, clazz, id) satisfies S11nContainerBuilder<Id> {
    ClassModel<Object> clazz;
    Id id;
    variable Integer index = 0;
    variable Type<Anything> elementType = `Nothing`;
    shared actual void addElement(Type<> et, Id element) {
        dc.element(id, index++, element);
        elementType = type(element).union(elementType);
    }
    shared actual Id instantiate(
        "A hint at the type originating from the metamodel"
        Type<> modelHint) {
        dc.instance(id, clazz);
        return id;
    }
}

shared class S11nDeserializer<out Instance>(Type<Instance> clazz, PropertyTypeHint? typeHinting) {
    
    value dc = deser<Integer>();
    variable value id = 0;
    Integer nextId() {
        value n = id;
        id++;
        return n;
    }
    
    variable PeekIterator<BasicEvent>? input = null;
    PeekIterator<BasicEvent> stream {
        assert(exists i=input);
        return i;
    }
    
    shared Instance deserialize(Iterator<BasicEvent>&Positioned input) {
        this.input = PeekIterator(input);
        return dc.reconstruct<Instance>(val(clazz));
    }
    
    "Peek at the next event in the stream and return the instance for it"
    Integer val(Type<> modelType) {
        //print("val(modelType=``modelType``)");
        switch (item=stream.peek)
        case (is ObjectStartEvent) {
            return obj(modelType);
        }
        case (is ArrayStartEvent) {
            // T is presumably some kind of X[], or Array<X> etc. 
            return arr(modelType);
        }
        case (is String) {
            stream.next();
            if (modelType.subtypeOf(`String|Null`)) {
                //print("val(modelType=``modelType``): ``item``");
                value n = nextId();
                dc.instanceValue(n, item);
                return n;
            }
            throw Exception("JSON value \"``item``\" cannot be coerced to ``modelType``");
        }
        case (is Integer) {
            stream.next();
            if (modelType.subtypeOf(`Integer|Null`)) {
                //print("val(modelType=``modelType``): ``item``");
                value n = nextId();
                dc.instanceValue(n, item);
                return n;
            }
            throw Exception("JSON value ``item`` cannot be coerced to ``modelType``");
        }
        case (is Float) {
            stream.next();
            if (modelType.subtypeOf(`Float|Null`)) {
                //print("val(modelType=``modelType``): ``item``");
                value n = nextId();
                dc.instanceValue(n, item);
                return n;
            }
            throw Exception("JSON value ``item`` cannot be coerced to ``modelType``");
        }
        case (is Boolean) {
            stream.next();
            if (modelType.subtypeOf(`Boolean|Null`)) {
                //print("val(modelType=``modelType``): ``item``");
                value n = nextId();
                dc.instanceValue(n, item);
                return n;
            }
            throw Exception("JSON value ``item`` cannot be coerced to ``modelType``");
        }
        case (is Null) {
            stream.next();
            if (modelType.subtypeOf(`Null`)) {
                //print("val(modelType=``modelType``): null");
                value n = nextId();
                dc.instanceValue(n, item);
                return n;
            }
            throw Exception("JSON value null cannot be coerced to ``modelType``");
        }
        else {
            throw Exception("Unexpected event ``item``");
        }
    }
    
    Integer arr(Type<> modelType) {
        //print("arr(modelType=``modelType``)");
        assert(stream.next() is ArrayStartEvent);// consume initial {
        // not a SequenceBuilder, something else
        //print(modelType);
        //assert(is ClassOrInterface<Object> modelType);
        S11nSequenceBuilder<Integer> builder = S11nSequenceBuilder<Integer>(dc, nextId(), nextId);
        //ArrayBuilder2<Integer> builder = ArrayBuilder2<Integer>(dc, `Array<String>`, nextId());
        while (true) {
            switch(item=stream.peek)
            case (is ObjectStartEvent|ArrayStartEvent|String|Null|Boolean|Float|Integer) {
                builder.addElement(iteratedType(modelType), val(iteratedType(modelType)));
            }
            case (is ArrayEndEvent) {
                stream.next();// consume ]
                value result = builder.instantiate(modelType);
                //print("arr(modelType=``modelType``): ``result``");
                return result;
            }
            case (is ObjectEndEvent|KeyEvent|Finished) {
                throw Exception("unexpected event ``item``");
            }
            
        }
    }
    
    function obtainBuilder(Type<> modelType, Type<> keyType) {
        Class<Object> clazz;// TODO use hints to figure out an instantiable class
        if (is Class<Object> k=keyType) {
            clazz = k;
        } else if (is Class<Object> m=modelType) {
            clazz = m;
        } else {
            clazz = nothing;
        }
        S11nBuilder<Integer> builder = S11nBuilder<Integer>(dc, clazz, nextId());// TODO reuse a single instance?
        return builder;
    }
    
    "Consume the next object from the [[stream]] and return the instance for it"
    Integer obj(Type<> modelType) {
        //print("obj(modelType=``modelType``)");
        assert(stream.next() is ObjectStartEvent);// consume initial {
        Type<> dataType;
        if (is PropertyTypeHint typeHinting) {
            // We ought to use any @type information we can obtain 
            // from the JSON object to inform the type we figure out for this attribute
            // but that requires (in general) that we buffer events until we reach
            // the @type, so we know the type of this object, so we can 
            // better figure out the type, of this attribute.
            // In practice we can ensure the serializer emits @type
            // as the first key, to keep such buffering to a minimum
            if (is KeyEvent k = stream.peek,
                k.eventValue == typeHinting.property) {
                stream.next();//consume @type
                if (is String typeName = stream.next()) {
                    dataType = typeHinting.naming.type(typeName);
                } else {
                    throw Exception("Expected String value for ``typeHinting.property`` property at ``stream.location``");
                }
            } else {
                dataType = `Nothing`;
            }
        } else {
            dataType = `Nothing`;
        }
        value m = eliminateNull(modelType);
        value d = eliminateNull(dataType);
        value builder = obtainBuilder(m, d);
        variable String? attributeName = null;
        while(true) {
            switch (item = stream.peek)
            case (is ObjectStartEvent) {
                assert(exists a=attributeName);
                builder.bindAttribute(a, obj(attributeType(modelType, dataType, a)));
                attributeName = null;
            }
            case (is ObjectEndEvent) {
                stream.next();// consume what we peeked
                return builder.instantiate();
            }
            case (is Finished) {
                throw Exception("unexpected end of stream");
            }
            case (is ArrayStartEvent) {
                assert(exists a=attributeName);
                builder.bindAttribute(a, arr(eliminateNull(attributeType(modelType, dataType, a))));
                attributeName = null;
            }
            case (is ArrayEndEvent) {
                "should never happen"
                assert(false);
            }
            case (is KeyEvent) {
                stream.next();// consume what we peeked
                //print("key: ``item.eventValue``");
                attributeName = item.eventValue;
            }
            case (is String|Integer|Float|Boolean|Null) {
                assert(exists a=attributeName);
                builder.bindAttribute(a, val(attributeType(modelType, dataType, a)));
                attributeName = null;
            }
        }
    }
}

shared void run() {
    value deserializer = S11nDeserializer {
        clazz = `S11nInvoice`;
        typeHinting = PropertyTypeHint{
            naming = LogicalTypeNaming(HashMap{
                "Person" -> `S11nPerson`,
                "Address" -> `S11nAddress`,
                "Item" -> `S11nItem`,
                "Product" -> `S11nProduct`,
                "Invoice" -> `S11nInvoice`
            });
        }; 
    };
    variable value times = 1000;
    variable value hs = 0;
    for (i in 1..times) {
        value x = deserializer.deserialize(StreamParser(StringTokenizer(exampleJson)));
        //print(x);
        hs+=x.hash; 
    }
    print("press enter");
    process.readLine();
    times = 4000;
    value t0 = system.nanoseconds;
    for (i in 1..times) {
        value x = deserializer.deserialize(StreamParser(StringTokenizer(exampleJson)));
        //print(x);
       hs+=x.hash; 
    }
    value elapsed = (system.nanoseconds - t0)/1_000_000.0;
    print("``elapsed``ms total");
    print("``elapsed/times``ms per deserialization");
    print(hs);
}




"Given a Type reflecting an Iterable, returns a Type reflecting the 
 iterated type or returns null if the given Type does not reflect an Iterable"
by("jvasileff")
Type<Anything> iteratedType(Type<Anything> containerType) {
    if (is ClassOrInterface<Anything> containerType,
        exists model = containerType.satisfiedTypes
                .narrow<Interface<Iterable<Anything>>>().first,
        exists x = model.typeArgumentList.first) {
        //print("iteratedType(containerType=``containerType``): ``x``");
        return x;
    }
    
    return `Nothing`;
}

"Figure out the type of the attribute of the given name that's a member of
 modelType or jsonType"
Type<> attributeType(Type<> modelType, Type<> jsonType, String attributeName) {
    Type<> type;
    if (!jsonType.exactly(`Nothing`)) {
        type = jsonType;
    } else if (is ClassOrInterface<> modelType) {
        type = modelType;
    } else {
        type = modelType.union(jsonType);
    }
    // since we know we're finding the type of an attribute on an object
    // we know that object can't be null
    Type<> qualifierType = eliminateNull(type);
    ////print("attributeType(``modelType``, ``jsonType``, ``attributeName``): qualifierType: ``qualifierType``");
    Type<> result;
    if (is ClassOrInterface<> qualifierType) {
        // We want to do qualifierType.getAttribute(), but we have to do it with runtime types
        // not compile time types, so we have to do go via the metamodel.
        //value r = `function ClassOrInterface.getAttribute`.memberInvoke(qualifierType, [qualifierType, `Anything`, `Nothing`], attributeName);
        //assert(is Attribute<Nothing, Anything, Nothing> r);
        //result = r.type;
        assert(exists a = qualifierType.getAttribute<Nothing,Anything,Nothing>(attributeName));
        return a.type;
    } else {
        result = `Nothing`;
    }
    //print("attributeType(``modelType``, ``jsonType``, ``attributeName``): result: ``result``");
    return result;
}


Type<> eliminateNull(Type<> type) {
    if (is UnionType<> type) {
        if (type.caseTypes.size == 2,
            exists nullIndex=type.caseTypes.firstOccurrence(`Null`)) {
            assert(exists definite = type.caseTypes[1-nullIndex]);
            return definite;
        } else {
            return type;
        }
    } else {
        return type;
    }
}