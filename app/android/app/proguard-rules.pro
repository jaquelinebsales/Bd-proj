# O plugin do ML Kit cita os leitores de chinês, japonês, coreano e devanágari, que o app não usa
# e que não vão no pacote (só o leitor de alfabeto latino). Sem estas linhas o R8 recusa o build.
-dontwarn com.google.mlkit.vision.text.chinese.**
-dontwarn com.google.mlkit.vision.text.devanagari.**
-dontwarn com.google.mlkit.vision.text.japanese.**
-dontwarn com.google.mlkit.vision.text.korean.**
