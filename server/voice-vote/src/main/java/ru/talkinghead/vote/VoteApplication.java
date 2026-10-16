package ru.talkinghead.vote;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;

@SpringBootApplication
public class VoteApplication {
    public static void main(String[] args) throws Exception {
        if(args.length>0 && args[0].equals("export-addon-ranking")) {
            AddonRanking.main(java.util.Arrays.copyOfRange(args,1,args.length));return;
        }
        if (args.length == 1 && args[0].equals("healthcheck")) {
            String port=System.getenv().getOrDefault("VOICE_VOTE_PORT","8081");
            try (var client=java.net.http.HttpClient.newBuilder().connectTimeout(java.time.Duration.ofSeconds(3)).build()) {
                var request=java.net.http.HttpRequest.newBuilder(java.net.URI.create("http://127.0.0.1:"+port+"/api/votes/health"))
                    .timeout(java.time.Duration.ofSeconds(3)).GET().build();
                var response=client.send(request,java.net.http.HttpResponse.BodyHandlers.ofString());
                if (response.statusCode()!=200 || !response.body().contains("talkinghead-vote-server"))
                    throw new IllegalStateException("Voting API health check failed");
            }
            return;
        }
        if (args.length > 0 && args[0].equals("export-results")) {
            ResultsExporter.main(java.util.Arrays.copyOfRange(args, 1, args.length));
            return;
        }
        var context = SpringApplication.run(VoteApplication.class, args);
        System.out.println("VOICE_VOTE_PORT=" + context.getEnvironment().getProperty("local.server.port"));
    }
}
