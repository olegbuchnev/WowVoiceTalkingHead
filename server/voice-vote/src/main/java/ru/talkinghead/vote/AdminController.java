package ru.talkinghead.vote;

import java.time.*;
import java.util.Map;
import org.springframework.http.HttpStatus;
import org.springframework.security.core.Authentication;
import org.springframework.security.web.csrf.CsrfToken;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.server.ResponseStatusException;

@RestController
@RequestMapping("/api/admin")
public class AdminController {
    private final VoteStore store;
    private final VoteInbox inbox;
    public AdminController(VoteStore store,VoteInbox inbox) {this.store=store;this.inbox=inbox;}
    @GetMapping("/session") public Map<String,Object> session(Authentication auth,CsrfToken csrf) {
        return Map.of("authenticated",auth!=null && auth.isAuthenticated(),"csrf",csrf.getToken(),"csrfHeader",csrf.getHeaderName());
    }
    @GetMapping("/inbox") public Map<String,Object> inbox() {return inbox.status();}
    private String since(int days) {
        if(days!=0 && days!=7 && days!=30 && days!=90) throw new ResponseStatusException(HttpStatus.BAD_REQUEST,"Invalid reporting period.");
        return days==0 ? "" : LocalDate.now(ZoneOffset.UTC).minusDays(days-1)+"T00:00:00";
    }
    @GetMapping("/dashboard") public Map<String,Object> dashboard(@RequestParam(defaultValue="30") int days) throws Exception {
        var report=store.dashboard(since(days));report.put("inbox",inbox.status());return report;
    }
    @GetMapping("/visitors") public Map<String,Object> visitors(@RequestParam(defaultValue="30") int days,
        @RequestParam(defaultValue="0") int offset,@RequestParam(defaultValue="") String search) throws Exception {
        if(offset<0 || offset>10000000 || !search.matches("[a-f0-9]{0,64}")) throw new ResponseStatusException(HttpStatus.BAD_REQUEST,"Invalid visitor query.");
        return store.adminVisitors(since(days),offset,search);
    }
    @GetMapping("/visitors/{id}") public Map<String,Object> visitor(@PathVariable String id,@RequestParam(defaultValue="0") int offset) throws Exception {
        if(!id.matches("[a-f0-9]{64}") || offset<0 || offset>10000000) throw new ResponseStatusException(HttpStatus.BAD_REQUEST,"Invalid visitor query.");
        return store.adminVisitor(id,offset);
    }
}
