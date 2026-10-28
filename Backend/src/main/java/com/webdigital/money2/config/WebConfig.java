package com.webdigital.money2.config;

import com.webdigital.money2.auth.AuthenticationInterceptor;
import org.springframework.context.annotation.Bean;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Configuration;
import org.springframework.web.filter.ShallowEtagHeaderFilter;
import org.springframework.web.servlet.config.annotation.CorsRegistry;
import org.springframework.web.servlet.config.annotation.InterceptorRegistry;
import org.springframework.web.servlet.config.annotation.WebMvcConfigurer;

@Configuration
public class WebConfig implements WebMvcConfigurer {

    private final AuthenticationInterceptor authenticationInterceptor;
    private final String[] allowedOriginPatterns;

    public WebConfig(
            AuthenticationInterceptor authenticationInterceptor,
            @Value("${money.cors.allowed-origin-patterns}")
            String[] allowedOriginPatterns) {
        this.authenticationInterceptor = authenticationInterceptor;
        this.allowedOriginPatterns = allowedOriginPatterns;
    }

    @Override
    public void addInterceptors(InterceptorRegistry registry) {
        registry.addInterceptor(authenticationInterceptor)
                .addPathPatterns("/api/v2/**")
                .excludePathPatterns(
                        "/api/v2/auth/signin",
                        "/api/v2/health");
    }

    @Override
    public void addCorsMappings(CorsRegistry registry) {
        registry.addMapping("/api/v2/**")
                .allowedOriginPatterns(allowedOriginPatterns)
                .allowedMethods("GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS")
                .allowedHeaders(
                        "Authorization",
                        "Content-Type",
                        "Accept",
                        "If-None-Match",
                        "Cache-Control")
                .exposedHeaders("ETag")
                .maxAge(3600);
    }

    @Bean
    public ShallowEtagHeaderFilter shallowEtagHeaderFilter() {
        ShallowEtagHeaderFilter filter = new ShallowEtagHeaderFilter();
        filter.setWriteWeakETag(true);
        return filter;
    }
}
