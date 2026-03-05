import java.io.*;
import javax.servlet.*;
import javax.servlet.http.*;
import javax.servlet.annotation.*;

@WebServlet(name = "EvaluateServlet", urlPatterns = {"/opencds-decision-support-service/evaluate"})
public class EvaluateServlet extends HttpServlet {
    
    @Override
    protected void doPost(HttpServletRequest request, HttpServletResponse response) 
            throws ServletException, IOException {
        
        response.setContentType("text/xml; charset=utf-8");
        response.setStatus(HttpServletResponse.SC_OK);
        
        // Read SOAP request
        StringBuilder soapRequest = new StringBuilder();
        try (BufferedReader reader = request.getReader()) {
            String line;
            while ((line = reader.readLine()) != null) {
                soapRequest.append(line).append("\n");
            }
        }
        
        // For now, return a mock response that matches OpenCDS format
        // TODO: Integrate with actual OpenCDS EvaluationSoapService
        String soapResponse = """<?xml version="1.0" encoding="UTF-8"?>
<soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/">
  <soapenv:Body>
    <evaluateResponse>
      <results>
        <assertion>
          <type>ALERT</type>
          <code>RED_FLAG_RESP</code>
          <message>Clinical evaluation recommended based on symptoms.</message>
          <severity>MEDIUM</severity>
        </assertion>
        <proposal>
          <type>lab_order</type>
          <code>LOINC:2093-3</code>
          <displayName>Complete Blood Count (CBC)</displayName>
          <rationale>Baseline assessment recommended.</rationale>
          <urgency>routine</urgency>
        </proposal>
        <proposal>
          <type>treatment</type>
          <code>MANAGEMENT</code>
          <displayName>Clinical monitoring</displayName>
          <treatmentType>management</treatmentType>
          <rationale>Continue monitoring symptoms.</rationale>
          <evidenceGrade>B</evidenceGrade>
        </proposal>
      </results>
    </evaluateResponse>
  </soapenv:Body>
</soapenv:Envelope>""";
        
        response.getWriter().write(soapResponse);
    }
    
    @Override
    protected void doGet(HttpServletRequest request, HttpServletResponse response) 
            throws ServletException, IOException {
        response.setContentType("text/html");
        response.getWriter().write("<h1>OpenCDS Evaluate Endpoint</h1><p>POST SOAP requests to this URL.</p>");
    }
}

