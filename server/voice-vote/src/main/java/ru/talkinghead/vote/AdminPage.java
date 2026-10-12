package ru.talkinghead.vote;

import org.springframework.stereotype.Controller;
import org.springframework.web.bind.annotation.GetMapping;

@Controller
public class AdminPage {
    @GetMapping({"/admin","/admin/"}) public String index() {return "forward:/admin/index.html";}
}
