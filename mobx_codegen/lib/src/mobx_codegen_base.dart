import 'dart:async';

import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/visitor.dart';
import 'package:build/build.dart';
import 'package:build/src/builder/build_step.dart';
import 'package:mobx_codegen/src/errors.dart';
import 'package:mobx_codegen/src/template/action.dart';
import 'package:mobx_codegen/src/template/computed.dart';
import 'package:mobx_codegen/src/template/observable.dart';
import 'package:mobx_codegen/src/template/store.dart';
import 'package:source_gen/source_gen.dart';
import 'package:mobx/mobx.dart' show Store;

import 'package:mobx/src/api/annotations.dart'
    show ComputedMethod, MakeAction, MakeObservable;

class StoreGenerator extends Generator {
  final _storeChecker = TypeChecker.fromRuntime(Store);

  @override
  FutureOr<String> generate(LibraryReader library, BuildStep buildStep) {
    final generate = (baseClass) sync* {
      final mixedClass = library.classes
          .firstWhere((c) => c.supertype == baseClass.type, orElse: () => null);
      if (mixedClass != null) {
        yield generateStoreClassCode(library, baseClass, mixedClass);
      }
    };

    return library.classes
        .where((c) => c.isAbstract)
        .where((c) => c.interfaces.any(_storeChecker.isExactlyType))
        .expand(generate)
        .toSet()
        .join('\n\n');
  }

  String generateStoreClassCode(
      LibraryReader library, ClassElement baseClass, ClassElement mixedClass) {
    final visitor = new StoreMixinVisitor(baseClass.name, mixedClass.name);
    baseClass.visitChildren(visitor);
    return visitor.source;
  }
}

class StoreMixinVisitor extends SimpleElementVisitor {
  StoreMixinVisitor(String parentName, String name)
      : _errors = StoreClassCodegenErrors(name) {
    _storeTemplate = StoreTemplate()
      ..parentName = parentName
      ..mixinName = '_\$$name';
  }

  final _observableChecker = TypeChecker.fromRuntime(MakeObservable);

  final _computedChecker = TypeChecker.fromRuntime(ComputedMethod);

  final _actionChecker = TypeChecker.fromRuntime(MakeAction);

  StoreTemplate _storeTemplate;

  final StoreClassCodegenErrors _errors;

  String get source {
    if (_errors.hasErrors) {
      log.severe(_errors.message);
      return '';
    }
    return _storeTemplate.toString();
  }

  @override
  visitFieldElement(FieldElement element) async {
    if (!_observableChecker.hasAnnotationOfExact(element)) {
      return null;
    }

    if (_fieldIsNotValid(element)) {
      return null;
    }

    final template = ObservableTemplate()
      ..storeTemplate = _storeTemplate
      ..atomName = '_\$${element.name}Atom'
      ..type = element.type.displayName
      ..name = element.name;

    _storeTemplate.observables.add(template);
    return null;
  }

  bool _fieldIsNotValid(FieldElement element) => any([
        _errors.staticObservables.addIf(element.isStatic, element.name),
        _errors.finalObservables.addIf(element.isFinal, element.name)
      ]);

  @override
  visitPropertyAccessorElement(PropertyAccessorElement element) {
    if (!element.isGetter || !_computedChecker.hasAnnotationOfExact(element)) {
      return null;
    }

    final template = ComputedTemplate()
      ..computedName = '_\$${element.name}Computed'
      ..name = element.name
      ..type = element.returnType.displayName;
    _storeTemplate.computeds.add(template);

    return null;
  }

  @override
  visitMethodElement(MethodElement element) {
    if (!_actionChecker.hasAnnotationOfExact(element)) {
      return null;
    }

    if (_methodIsNotValid(element)) {
      return null;
    }

    final typeParam = (TypeParameterElement elem) => TypeParamTemplate()
      ..name = elem.name
      ..bound = elem.bound?.displayName;

    final param = (ParameterElement elem) => ParamTemplate()
      ..name = elem.name
      ..type = elem.type.displayName
      ..defaultValue = elem.defaultValueCode;

    final positionalParams = element.parameters
        .where((param) => param.isPositional && !param.isOptionalPositional)
        .toList();

    final optionalParams = element.parameters
        .where((param) => param.isOptionalPositional)
        .toList();

    final namedParams =
        element.parameters.where((param) => param.isNamed).toList();

    final template = ActionTemplate()
      ..storeTemplate = _storeTemplate
      ..name = element.name
      ..returnType = element.returnType.displayName
      ..typeParams = element.typeParameters.map(typeParam)
      ..positionalParams = positionalParams.map(param)
      ..optionalParams = optionalParams.map(param)
      ..namedParams = namedParams.map(param);

    _storeTemplate.actions.add(template);

    return null;
  }

  bool _methodIsNotValid(MethodElement element) => any([
        _errors.staticActions.addIf(element.isStatic, element.name),
        _errors.asyncActions.addIf(element.isAsynchronous, element.name),
      ]);
}

bool any(List<bool> list) => list.any(identity);

T identity<T>(T value) => value;
