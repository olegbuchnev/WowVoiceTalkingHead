package ru.talkinghead.vote;

import java.io.ByteArrayInputStream;
import java.io.IOException;
import jakarta.servlet.*;
import jakarta.servlet.http.*;
import org.springframework.stereotype.Component;
import org.springframework.web.filter.OncePerRequestFilter;

@Component
public class BallotSizeFilter extends OncePerRequestFilter {
    @Override protected void doFilterInternal(HttpServletRequest request, HttpServletResponse response,
            FilterChain chain) throws ServletException, IOException {
        if (!request.getMethod().equals("POST") || !request.getRequestURI().startsWith("/api/votes")) {
            chain.doFilter(request,response); return;
        }
        // Bound chunked requests too, before Jackson allocates an object tree.
        byte[] bytes=request.getInputStream().readNBytes(16 * 1024 + 1);
        if (bytes.length > 16 * 1024) {
            response.setStatus(413); response.setContentType("application/json;charset=UTF-8");
            response.setHeader("Cache-Control","no-store");
            response.getWriter().write("{\"error\":\"Request body is too large.\"}"); return;
        }
        chain.doFilter(new HttpServletRequestWrapper(request) {
            @Override public ServletInputStream getInputStream() {
                var input=new ByteArrayInputStream(bytes);
                return new ServletInputStream() {
                    @Override public int read() {return input.read();}
                    @Override public boolean isFinished() {return input.available()==0;}
                    @Override public boolean isReady() {return true;}
                    @Override public void setReadListener(ReadListener listener) {throw new UnsupportedOperationException();}
                };
            }
        }, response);
    }
}
