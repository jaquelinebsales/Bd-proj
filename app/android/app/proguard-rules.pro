# O plugin do ML Kit cita os leitores de chinês, japonês, coreano e devanágari, que o app não usa
# e que não vão no pacote (só o leitor de alfabeto latino). Sem estas linhas o R8 recusa o build.
-dontwarn com.google.mlkit.vision.text.chinese.**
-dontwarn com.google.mlkit.vision.text.devanagari.**
-dontwarn com.google.mlkit.vision.text.japanese.**
-dontwarn com.google.mlkit.vision.text.korean.**

# Mapa (pacote maplibre): o código Dart chama as classes do plugin pelo nome, via JNI
# (com/github/josxha/maplibre/MapLibreRegistry, FlutterApi...). As regras do pacote só preservam org.maplibre.**;
# sem esta linha o R8 renomeia o plugin no APK de release e o mapa nunca é criado (tela vazia).
-keep class com.github.josxha.maplibre.** { *; }
-keep interface com.github.josxha.maplibre.** { *; }
# Classes que aparecem nas assinaturas chamadas por JNI: os nomes precisam continuar iguais no APK
-keep class kotlin.coroutines.Continuation { *; }
-keep class kotlin.jvm.internal.** { *; }
-keep class kotlinx.coroutines.CoroutineScope { *; }
-keep class androidx.fragment.app.** { *; }
