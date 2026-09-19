package com.dreynox.herramienta_shaiya

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.provider.DocumentsContract
import android.provider.OpenableColumns
import android.os.ParcelFileDescriptor
import java.nio.ByteBuffer
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.Executors

/** Acceso SAF de solo lectura. Nunca solicita MANAGE_EXTERNAL_STORAGE. */
class MainActivity : FlutterActivity() {
    private val workers = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    private var pendingPicker: MethodChannel.Result? = null
    private val archiveUris = ConcurrentHashMap<String, Long>()
    private val indexed = ConcurrentHashMap<String, Set<String>>()
    private val extensions = setOf("sdata", "svmap", "env", "seff", "wtr", "vani", "3de", "ini", "xml", "cfg", "3dc", "3do", "ani", "mlt", "alt", "itm", "mon", "dds", "png", "jpg", "jpeg", "tga", "bmp", "wav", "mp3", "ogg", "wld", "smod", "dg", "eft")
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "dreynox.shaiya/data").setMethodCallHandler { call, result ->
            when (call.method) {
                "chooseTree" -> {
                    if (pendingPicker != null) { result.error("busy", "Ya hay un selector abierto.", null) }
                    else {
                        pendingPicker = result
                        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE)
                        intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION or Intent.FLAG_GRANT_PREFIX_URI_PERMISSION)
                        try { startActivityForResult(intent, 7201) }
                        catch (e: Exception) { pendingPicker = null; result.error("picker", e.message, null) }
                    }
                }
                "chooseArchive" -> {
                    if (pendingPicker != null) { result.error("busy", "Ya hay un selector abierto.", null) }
                    else {
                        pendingPicker = result
                        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                            type = "*/*"
                            addCategory(Intent.CATEGORY_OPENABLE)
                            putExtra(Intent.EXTRA_ALLOW_MULTIPLE, true)
                            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION)
                        }
                        try { startActivityForResult(intent, 7202) }
                        catch (e: Exception) { pendingPicker = null; result.error("picker", e.message, null) }
                    }
                }
                "archiveRead" -> {
                    val target = call.argument<String>("uri") ?: ""
                    val offset = call.argument<Number>("offset")?.toLong() ?: -1L
                    val length = call.argument<Number>("length")?.toInt() ?: -1
                    async(result) {
                        val originalSize = archiveUris[target] ?: error("Archivo no autorizado por el selector.")
                        require(offset >= 0 && length in 0..67108864 && offset <= originalSize && length.toLong() <= originalSize - offset) { "Rango de archivo fuera de límite." }
                        val pfd = contentResolver.openFileDescriptor(Uri.parse(target), "r") ?: error("No se pudo abrir el archivo en modo lectura.")
                        ParcelFileDescriptor.AutoCloseInputStream(pfd).use { stream ->
                                val channel = stream.channel
                                require(channel.size() == originalSize) { "El archivo cambió después de seleccionarlo." }
                                val output = ByteArray(length)
                                val buffer = ByteBuffer.wrap(output)
                                var position = offset
                                while (buffer.hasRemaining()) {
                                    val n = channel.read(buffer, position)
                                    check(n > 0) { "Lectura incompleta. El proveedor puede no admitir acceso aleatorio; utiliza almacenamiento local." }
                                    position += n
                                }
                                output
                        }
                    }
                }
                "index" -> {
                    val tree = call.argument<String>("tree")
                    if (tree == null) { result.error("input", "Falta la carpeta autorizada.", null) }
                    else async(result) {
                        val uri = Uri.parse(tree)
                        require(uri.scheme == "content" && DocumentsContract.isTreeUri(uri)) { "No es una carpeta SAF." }
                        val entries = LinkedHashMap<String, String>()
                        val queue = java.util.ArrayDeque<Pair<String, String>>()
                        val visited = HashSet<String>()
                        queue.add(Pair(DocumentsContract.getTreeDocumentId(uri), ""))
                        while (queue.isNotEmpty()) {
                            val (parent, prefix) = queue.removeFirst()
                            if (!visited.add(parent)) continue
                            require(visited.size < 25000) { "Demasiadas subcarpetas." }
                            val children = DocumentsContract.buildChildDocumentsUriUsingTree(uri, parent)
                            contentResolver.query(children, arrayOf(DocumentsContract.Document.COLUMN_DOCUMENT_ID, DocumentsContract.Document.COLUMN_DISPLAY_NAME, DocumentsContract.Document.COLUMN_MIME_TYPE), null, null, null)?.use { cursor ->
                                while (cursor.moveToNext()) {
                                    val id = cursor.getString(0) ?: continue
                                    val name = cursor.getString(1) ?: continue
                                    require(name != "." && name != ".." && !name.contains('/') && !name.contains('\\')) { "Nombre de recurso inválido." }
                                    val path = if (prefix.isEmpty()) name else "$prefix/$name"
                                    if (cursor.getString(2) == DocumentsContract.Document.MIME_TYPE_DIR) queue.add(Pair(id, path))
                                    else if (name.substringAfterLast('.', "").lowercase() in extensions) {
                                        require(entries.size < 200000) { "Se superó el límite de recursos." }
                                        entries[path] = DocumentsContract.buildDocumentUriUsingTree(uri, id).toString()
                                    }
                                }
                            } ?: error("El proveedor no permitió listar $prefix.")
                        }
                        // Preserve the prior connection until Dart commits a new scene.
                        indexed[tree] = entries.values.toHashSet()
                        entries
                    }
                }
                "read" -> {
                    val tree = call.argument<String>("tree") ?: ""
                    val target = call.argument<String>("uri") ?: ""
                    val maximum = (call.argument<Number>("limit")?.toInt() ?: 67108864).coerceIn(1, 67108864)
                    async(result) {
                        require(indexed[tree]?.contains(target) == true) { "El recurso no pertenece a la biblioteca indexada." }
                        val output = ByteArrayOutputStream()
                        contentResolver.openInputStream(Uri.parse(target))?.use { input ->
                            val buffer = ByteArray(65536)
                            var count = input.read(buffer)
                            while (count >= 0) {
                                require(output.size() + count <= maximum) { "El archivo supera el límite de memoria." }
                                output.write(buffer, 0, count)
                                count = input.read(buffer)
                            }
                        } ?: error("El proveedor no permitió leer el archivo.")
                        output.toByteArray()
                    }
                }
                else -> result.notImplemented()
            }
        }
    }
    private fun async(result: MethodChannel.Result, work: () -> Any) {
        workers.execute {
            try { val value = work(); main.post { result.success(value) } }
            catch (e: Exception) { main.post { result.error("data", e.message ?: "Error de lectura.", null) } }
        }
    }
    @Deprecated("Activity result bridge for the platform folder picker")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != 7201 && requestCode != 7202) return
        val callback = pendingPicker ?: return
        pendingPicker = null
        if (requestCode == 7202) {
            if (resultCode != Activity.RESULT_OK || data == null) { callback.success(null); return }
            val uris = mutableListOf<Uri>()
            val clip = data.clipData
            if (clip != null) { for (i in 0 until clip.itemCount) uris.add(clip.getItemAt(i).uri) }
            else data.data?.let { uris.add(it) }
            async(callback) {
                require(uris.size == 2) { "Selecciona simultáneamente el SAH y el SAF (mantén pulsado para selección múltiple)." }
                val pair = HashMap<String, Any>()
                for (uri in uris) {
                    var name = ""
                    contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { c -> if(c.moveToFirst()) name=c.getString(0) ?: "" }
                    val ext = name.substringAfterLast('.', "").lowercase()
                    require(ext in setOf("sah", "saf") && !pair.containsKey(ext)) { "Se necesita exactamente un índice .sah y un archivo .saf." }
                    val size = contentResolver.openFileDescriptor(uri,"r")?.use { pfd ->
                        ParcelFileDescriptor.AutoCloseInputStream(pfd).use { it.channel.size() }
                    } ?: error("El proveedor no permite leer el tamaño del archivo.")
                    require(size >= 0 && (ext != "sah" || size <= 67108864L)) { "Índice demasiado grande o tamaño no disponible." }
                    // Session grant is sufficient if the provider cannot persist it.
                    try { contentResolver.takePersistableUriPermission(uri, Intent.FLAG_GRANT_READ_URI_PERMISSION) } catch (_: SecurityException) { }
                    archiveUris[uri.toString()] = size
                    pair[ext] = mapOf("uri" to uri.toString(), "name" to name, "size" to size)
                }
                pair
            }
            return
        }
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) { callback.success(null); return }
        try {
            contentResolver.takePersistableUriPermission(uri, Intent.FLAG_GRANT_READ_URI_PERMISSION)
            callback.success(uri.toString())
        } catch (e: Exception) { callback.error("permission", "No se pudo conservar el permiso de lectura: ${e.message}", null) }
    }
    override fun onDestroy() { pendingPicker?.success(null); pendingPicker = null; workers.shutdown(); super.onDestroy() }
}
