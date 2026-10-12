package ru.talkinghead.vote;

import java.io.ByteArrayOutputStream;
import java.nio.file.Path;
import java.util.Set;
import java.util.concurrent.Semaphore;
import java.util.zip.*;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.*;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.server.ResponseStatusException;

@RestController
@RequestMapping("/api/admin/export")
public class AdminExportController {
    private final Path database,catalogue;
    private final Semaphore exporting=new Semaphore(1);
    public AdminExportController(@Value("${voice-vote.database}") String database,@Value("${voice-vote.catalogue}") String catalogue) {
        this.database=Path.of(database);this.catalogue=Path.of(catalogue);
    }
    @GetMapping("/{file}") public ResponseEntity<byte[]> download(@PathVariable String file) throws Exception {
        if(!Set.of("results.json","quests.csv","race-sex.csv","pairwise.csv","results.zip").contains(file))
            throw new ResponseStatusException(HttpStatus.NOT_FOUND,"Unknown export format.");
        if(!exporting.tryAcquire()) throw new ResponseStatusException(HttpStatus.TOO_MANY_REQUESTS,"An export is already running.");
        try {
            var files=ResultsExporter.files(ResultsExporter.read(database,catalogue));
            byte[] bytes;
            if(file.endsWith(".zip")) {
                var buffer=new ByteArrayOutputStream();
                try(var zip=new ZipOutputStream(buffer)) {
                    for(var entry:files.entrySet()) {zip.putNextEntry(new ZipEntry(entry.getKey()));zip.write(entry.getValue());zip.closeEntry();}
                }
                bytes=buffer.toByteArray();
            } else bytes=files.get(file);
            String type=file.endsWith(".zip")?"application/zip":file.endsWith(".json")?"application/json":"text/csv;charset=UTF-8";
            return ResponseEntity.ok().header(HttpHeaders.CONTENT_DISPOSITION,"attachment; filename=\""+file+"\"")
                .header(HttpHeaders.CACHE_CONTROL,"no-store").contentType(MediaType.parseMediaType(type)).body(bytes);
        } finally {exporting.release();}
    }
}
