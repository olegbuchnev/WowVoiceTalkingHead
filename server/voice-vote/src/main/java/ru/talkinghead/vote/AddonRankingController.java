package ru.talkinghead.vote;

import java.nio.file.Path;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

@RestController
@RequestMapping("/api/votes/ranking")
public class AddonRankingController {
    private final Path database,catalogue;
    private final VoteStore store;
    private AddonRanking.Export cached;
    private long expires;
    public AddonRankingController(@Value("${voice-vote.database}") String database,@Value("${voice-vote.catalogue}") String catalogue,VoteStore store) {
        this.database=Path.of(database);this.catalogue=Path.of(catalogue);
        this.store=store;
    }
    private synchronized AddonRanking.Export snapshot() throws Exception {
        if(cached==null || System.nanoTime()>=expires) {store.synchronizeRanking();cached=AddonRanking.export(database,catalogue);expires=System.nanoTime()+10_000_000_000L;}
        return cached;
    }
    @GetMapping(produces="application/json") public ResponseEntity<String> json() throws Exception {
        return ResponseEntity.ok().header("Cache-Control","no-store").header("Content-Disposition","attachment; filename=addon-voice-ranking.json").body(snapshot().json());
    }
    @GetMapping("/export") public ResponseEntity<AddonRanking.Export> bundle() throws Exception {
        return ResponseEntity.ok().header("Cache-Control","no-store").body(snapshot());
    }
    @ExceptionHandler(Exception.class) public ResponseEntity<?> unavailable(Exception error) {
        org.slf4j.LoggerFactory.getLogger(getClass()).error("Ranking export failed",error);
        return ResponseEntity.status(503).header("Cache-Control","no-store").body(java.util.Map.of("error","Ranking export unavailable. Retry later."));
    }
}
