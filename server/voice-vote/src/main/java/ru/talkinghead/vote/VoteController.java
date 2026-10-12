package ru.talkinghead.vote;

import java.time.Duration;
import java.util.Arrays;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseCookie;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.server.ResponseStatusException;

@RestController
@RequestMapping("/api/votes")
public class VoteController {
    public record Ballot(long questID, String selectedId, List<String> variantIds, String visitID) {
        public Ballot(long questID,String selectedId,List<String> variantIds) {this(questID,selectedId,variantIds,null);}
    }
    public record Playback(String visitID,long questID,String recordingID) {}
    private final VoteStore store;
    private final Catalogue catalogue;
    private final VoteInbox inbox;
    private final boolean secureCookie;
    public VoteController(VoteStore store, Catalogue catalogue, VoteInbox inbox, @Value("${voice-vote.secure-cookie}") boolean secureCookie) {
        this.store = store; this.catalogue = catalogue; this.inbox=inbox; this.secureCookie = secureCookie;
    }
    private String visitor(HttpServletRequest request) throws Exception {
        String token = request.getCookies() == null ? null : Arrays.stream(request.getCookies())
            .filter(c -> c.getName().equals("talkinghead_voter")).map(c -> c.getValue()).findFirst().orElse(null);
        return store.visitor(token);
    }
    @GetMapping("/health") public Map<String,String> health() { return Map.of("app", "talkinghead-vote-server"); }
    @GetMapping("/summary") public VoteStore.Summary summary(HttpServletRequest request, HttpServletResponse response) throws Exception {
        response.setHeader("Cache-Control", "no-store");
        String id = visitor(request);
        if (id == null) {
            var created = store.createVisitor(); id = created.id();
            response.addHeader("Set-Cookie", ResponseCookie.from("talkinghead_voter", created.token())
                .httpOnly(true).secure(secureCookie || request.isSecure()).sameSite("Lax").path("/")
                .maxAge(Duration.ofDays(365)).build().toString());
        }
        return store.summary(id);
    }
    @GetMapping("/queue") public List<VoteStore.Priority> queue(HttpServletRequest request, HttpServletResponse response) throws Exception {
        response.setHeader("Cache-Control", "no-store");
        String id = visitor(request);
        if (id == null) throw new ResponseStatusException(HttpStatus.UNAUTHORIZED, "Allow site cookies and reload the page.");
        var quests=catalogue.quests();var pending=inbox.pendingQuests(id,quests);
        return store.queue(id,quests).stream().map(p->new VoteStore.Priority(p.questID(),p.rated() || pending.contains(p.questID()),p.votes()))
            .sorted(java.util.Comparator.comparing(VoteStore.Priority::rated).thenComparingLong(VoteStore.Priority::votes)).toList();
    }
    @PostMapping(value={"","/submit"},consumes="application/json")
    public Object vote(@RequestBody Ballot ballot, HttpServletRequest request, HttpServletResponse response) throws Exception {
        response.setHeader("Cache-Control", "no-store");
        String origin = request.getHeader("Origin"), host = request.getHeader("Host");
        if (!List.of("http://" + host, "https://" + host).contains(origin == null ? "" : origin)
            || "cross-site".equals(request.getHeader("Sec-Fetch-Site")))
            throw new ResponseStatusException(HttpStatus.FORBIDDEN, "The request must originate from this site.");
        String id = visitor(request);
        if (id == null) throw new ResponseStatusException(HttpStatus.UNAUTHORIZED, "Allow site cookies and reload the page.");
        if (ballot.questID() <= 0 || ballot.selectedId() == null || !ballot.selectedId().matches("[a-f0-9]{24}")
            || ballot.variantIds() == null || ballot.variantIds().size() < 2 || ballot.variantIds().size() > 3
            || ballot.variantIds().stream().anyMatch(v -> v == null || !v.matches("[a-f0-9]{24}"))
            || new HashSet<>(ballot.variantIds()).size() != ballot.variantIds().size())
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "Invalid ballot.");
        var quest = catalogue.verified(ballot.questID(), ballot.selectedId(), ballot.variantIds());
        if(ballot.visitID()!=null && !ballot.visitID().matches("[a-f0-9-]{36}"))
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST,"Invalid visit identifier.");
        if(request.getRequestURI().endsWith("/submit"))
            return ResponseEntity.accepted().body(inbox.accept(id,quest,ballot.selectedId(),ballot.visitID()));
        return store.save(id, quest, ballot.selectedId(),ballot.visitID());
    }
    @PostMapping("/playback") public Map<String,Boolean> playback(@RequestBody Playback event,HttpServletRequest request) throws Exception {
        String origin=request.getHeader("Origin"),host=request.getHeader("Host");
        if(!List.of("http://"+host,"https://"+host).contains(origin==null?"":origin))
            throw new ResponseStatusException(HttpStatus.FORBIDDEN,"The request must originate from this site.");
        String id=visitor(request);
        if(id==null) throw new ResponseStatusException(HttpStatus.UNAUTHORIZED,"Visitor cookie required.");
        if(event.visitID()==null || !event.visitID().matches("[a-f0-9-]{36}") || event.recordingID()==null)
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST,"Invalid playback event.");
        var quest=catalogue.quests().stream().filter(q->q.questID()==event.questID()
            && q.variants().stream().anyMatch(v->v.id().equals(event.recordingID()))).findFirst()
            .orElseThrow(()->new ResponseStatusException(HttpStatus.NOT_FOUND,"Recording not found."));
        store.visit(id,event.visitID(),"play","",quest,event.recordingID());
        return Map.of("saved",true);
    }
    @ExceptionHandler(ResponseStatusException.class)
    public ResponseEntity<?> expected(ResponseStatusException error,HttpServletRequest request) {
        if(request.getRequestURI().endsWith("/submit")) inbox.rejected(error);
        return ResponseEntity.status(error.getStatusCode()).header("Cache-Control","no-store")
            .body(Map.of("error", error.getReason() == null ? "Invalid request." : error.getReason()));
    }
    @ExceptionHandler(org.springframework.http.converter.HttpMessageNotReadableException.class)
    public ResponseEntity<?> malformed() {
        return ResponseEntity.badRequest().header("Cache-Control","no-store")
            .body(Map.of("error", "Invalid ballot."));
    }
    @ExceptionHandler(Exception.class)
    public ResponseEntity<?> unavailable(Exception error,HttpServletRequest request) {
        if(request.getRequestURI().endsWith("/submit")) inbox.rejected(error);
        org.slf4j.LoggerFactory.getLogger(VoteController.class).warn("Voting request failed", error);
        return ResponseEntity.status(503).header("Cache-Control","no-store")
            .body(Map.of("error", "Could not save or load votes. Please try again."));
    }
}
