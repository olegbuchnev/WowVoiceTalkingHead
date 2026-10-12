package ru.talkinghead.vote;

import java.nio.file.*;
import java.util.concurrent.atomic.AtomicInteger;
import java.io.IOException;
import jakarta.servlet.*;
import jakarta.servlet.http.*;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.*;
import org.springframework.security.config.annotation.web.builders.HttpSecurity;
import org.springframework.security.web.SecurityFilterChain;
import org.springframework.security.core.userdetails.*;
import org.springframework.security.provisioning.InMemoryUserDetailsManager;
import org.springframework.security.crypto.bcrypt.BCryptPasswordEncoder;
import org.springframework.security.web.authentication.UsernamePasswordAuthenticationFilter;
import org.springframework.web.filter.OncePerRequestFilter;

@Configuration
public class AdminSecurity {
    @Bean org.springframework.security.crypto.password.PasswordEncoder adminEncoder() {return new BCryptPasswordEncoder(12);}
    @Bean UserDetailsService adminUsers(@Value("${voice-vote.admin-password-file}") String file) throws IOException {
        var users=new InMemoryUserDetailsManager();
        if(!file.isBlank() && Files.isRegularFile(Path.of(file))) {
            String password=Files.readString(Path.of(file)).strip();
            if(password.length()<20 || password.length()>64) throw new IllegalArgumentException("Admin password must contain 20 to 64 characters");
            users.createUser(User.withUsername("admin").password(new BCryptPasswordEncoder(12).encode(password)).roles("ADMIN").build());
        }
        return users;
    }
    @Bean SecurityFilterChain adminChain(HttpSecurity http) throws Exception {
        http.securityMatcher("/api/admin/**","/admin/**","/admin")
            .authorizeHttpRequests(auth->auth.requestMatchers("/admin","/admin/**","/api/admin/session","/api/admin/login").permitAll().anyRequest().hasRole("ADMIN"))
            .requestCache(cache->cache.disable())
            .headers(headers->headers.contentSecurityPolicy(csp->csp.policyDirectives("default-src 'self'; script-src 'self'; style-src 'self' 'unsafe-inline'; img-src 'self' data:; frame-ancestors 'none'; base-uri 'self'; form-action 'self'")))
            .formLogin(form->form.loginPage("/admin/").loginProcessingUrl("/api/admin/login")
                .successHandler((request,response,authentication)->json(response,200,"{\"authenticated\":true}"))
                .failureHandler((request,response,error)->json(response,401,"{\"error\":\"Invalid credentials.\"}")))
            .logout(logout->logout.logoutUrl("/api/admin/logout").logoutSuccessHandler((request,response,authentication)->json(response,200,"{\"authenticated\":false}")))
            .exceptionHandling(errors->errors.authenticationEntryPoint((request,response,error)->json(response,401,"{\"error\":\"Authentication required.\"}"))
                .accessDeniedHandler((request,response,error)->json(response,403,"{\"error\":\"Request denied.\"}")))
            .addFilterBefore(new LoginLimit(),UsernamePasswordAuthenticationFilter.class);
        return http.build();
    }
    static void json(HttpServletResponse response,int status,String json) throws IOException {
        response.setStatus(status);response.setContentType("application/json;charset=UTF-8");
        response.setHeader("Cache-Control","no-store");response.getWriter().write(json);
    }
    private static class LoginLimit extends OncePerRequestFilter {
        private long window=System.currentTimeMillis();
        private final AtomicInteger attempts=new AtomicInteger();
        private synchronized boolean allowed() {
            if(System.currentTimeMillis()-window>=60000) {window=System.currentTimeMillis();attempts.set(0);}
            return attempts.incrementAndGet()<=20;
        }
        @Override protected void doFilterInternal(HttpServletRequest request,HttpServletResponse response,FilterChain chain) throws ServletException,IOException {
            response.setHeader("Cache-Control","no-store");
            if(request.getRequestURI().equals("/api/admin/login") && request.getMethod().equals("POST") && !allowed()) {
                response.setHeader("Retry-After","60");json(response,429,"{\"error\":\"Too many login attempts. Try again later.\"}");return;
            }
            chain.doFilter(request,response);
        }
    }
}
